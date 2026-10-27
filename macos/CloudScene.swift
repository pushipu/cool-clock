import Foundation
import simd

struct CloudWindowState {
    var rectangle: SIMD4<Double>
    var before: Int
    var after: Int
    var weight: Double
}

struct CloudSceneFrame {
    var background: Int
    var windows: [CloudWindowState]
    var takeoverTarget: Int?
    var coverage: [SIMD4<Double>]
    var luts: [SIMD4<UInt8>]
}

struct CloudScene {
    static let duration = 116.0
    static let sourceDuration = 29.0
    static let handoffInterval = duration / 14
    static let motionScale = (duration / 3) / 30
    private static let initialWindows = [1, 2, 3, 4, 1, 5, 6]
    private let tracks: [[SIMD4<Double>]]
    private static let light = (0..<256).map { pow(min(1, max(0, (Double($0) - 20) / 215)), 1.3) }
    private static let colors: [SIMD3<Double>] = [
        SIMD3(65, 122, 240), SIMD3(215, 225, 242), SIMD3(100, 171, 255),
        SIMD3(41, 66, 135), SIMD3(114, 186, 255), SIMD3(51, 79, 151)
    ]
    private static let exposure = [1.0, 1.16, 1.12, 0.72, 1.15, 0.72]

    private struct Handoff {
        let start: Double
        let end: Double
        let target: Int
        let participants: [Int]
        let following: [Int]
    }

    private static let handoffs: [Handoff] = {
        let patterns = [
            (1, [0, 1, 3, 4, 6], [3, 2, 4, 0, 6, 5, 2]),
            (2, [1, 3, 6], [6, 5, 1, 0, 3, 4, 1]),
            (1, [1, 2, 3, 6], [3, 2, 4, 0, 6, 5, 2]),
            (0, [1, 3, 6], initialWindows)
        ]
        return [0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3, 0, 3].enumerated().map { index, pattern in
            let value = patterns[pattern]
            return Handoff(start: 4 + Double(index) * handoffInterval,
                           end: 6.08 + Double(index) * handoffInterval,
                           target: value.0, participants: value.1, following: value.2)
        }
    }()

    init(bundle: Bundle) throws {
        guard let url = bundle.url(forResource: "RectangleTracks", withExtension: "json") else {
            throw NSError(domain: "CoolClock", code: 50, userInfo: [NSLocalizedDescriptionKey: "RectangleTracks.json is missing"])
        }
        try self.init(data: Data(contentsOf: url))
    }

    init(data: Data) throws {
        let values = try JSONDecoder().decode([[[Double]]].self, from: data)
        guard values.count == 7, values.allSatisfy({ track in
            track.count == 6 && track.allSatisfy { rectangle in
                rectangle.count == 4 && rectangle.allSatisfy(\.isFinite)
                    && rectangle[0] >= 0 && rectangle[0] < rectangle[2] && rectangle[2] <= 984
                    && rectangle[1] >= 0 && rectangle[1] < rectangle[3] && rectangle[3] <= 718
            }
        }) else {
            throw NSError(domain: "CoolClock", code: 51, userInfo: [NSLocalizedDescriptionKey: "Invalid rectangle tracks"])
        }
        tracks = values.map { $0.map { SIMD4($0[0], $0[1], $0[2], $0[3]) } }
    }

    static func wrap(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        let value = seconds.truncatingRemainder(dividingBy: duration)
        return value < 0 ? value + duration : value
    }

    private static func ease(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return x * x * (3 - 2 * x)
    }

    private static func phase(_ seconds: Double) -> (Int, Double) {
        let position = (wrap(seconds) * 3 / duration).truncatingRemainder(dividingBy: 1) * 6
        let index = Int(position)
        return (index, ease(position - Double(index)))
    }

    private func rectangle(_ track: Int, at seconds: Double) -> SIMD4<Double> {
        let (index, weight) = Self.phase(seconds)
        let values = tracks[track]
        return values[index] + (values[(index + 1) % 6] - values[index]) * weight
    }

    private func coverage(_ event: Handoff, at seconds: Double) -> [SIMD4<Double>] {
        let progress = min(1, max(0, (seconds - event.start) / (event.end - event.start)))
        let seeds = [1, 3, 6].map { rectangle($0, at: event.start) }
        let rows = [0, (seeds[0].w + seeds[1].y) / 2, (seeds[1].w + seeds[2].y) / 2, 718]
        let columns = [0.0, 244, 739, 984]
        var result: [SIMD4<Double>] = []
        for column in 0..<3 {
            let left = columns[column], right = columns[column + 1]
            for (row, seed) in seeds.enumerated() {
                let initial = SIMD4(min(right, max(left, seed.x)), seed.y,
                                    min(right, max(left, seed.z)), seed.w)
                let destination = SIMD4(left, rows[row], right, rows[row + 1])
                let delay = 0.07 * Double((column + 2 * row) % 5)
                let weight = Self.ease((progress - delay) / (1 - delay))
                result.append(initial * (1 - weight) + destination * weight)
            }
        }
        return result
    }

    private static func lut(at seconds: Double, inner: Bool) -> [SIMD4<UInt8>] {
        let (colorIndex, colorWeight) = phase(seconds + (inner ? motionScale : 0))
        let white = colors[colorIndex] + (colors[(colorIndex + 1) % 6] - colors[colorIndex]) * colorWeight
        let (exposureIndex, exposureWeight) = phase(seconds)
        let brightness = exposure[exposureIndex] + (exposure[(exposureIndex + 1) % 6] - exposure[exposureIndex]) * exposureWeight
        let black = SIMD3<Double>(3, 7, 23)
        return light.map { value in
            let color = black + min(1, max(0, value * brightness)) * (white - black)
            return SIMD4(UInt8(min(255, max(0, color.x))), UInt8(min(255, max(0, color.y))),
                         UInt8(min(255, max(0, color.z))), 255)
        }
    }

    func frame(at seconds: Double) -> CloudSceneFrame {
        let time = Self.wrap(seconds)
        var background = 0, sources = Self.initialWindows
        var windows: [CloudWindowState] = []
        var active: Handoff?
        for event in Self.handoffs {
            if time < event.start - 0.65 * 1.3 { break }
            let staged = sources.enumerated().map { event.participants.contains($0.offset) ? event.target : $0.element }
            if time < event.start {
                let weight = Self.ease((time - event.start + 0.65 * 1.3) / (0.65 * 1.3))
                windows = (0..<7).map { CloudWindowState(rectangle: rectangle($0, at: time), before: sources[$0], after: staged[$0], weight: weight) }
                break
            }
            if time < event.end {
                windows = (0..<7).map { CloudWindowState(rectangle: rectangle($0, at: time), before: staged[$0], after: staged[$0], weight: 0) }
                active = event
                break
            }
            background = event.target
            if time < event.end + 0.25 * 1.3 + 1.2 * 1.3 {
                windows = (0..<7).map { index in
                    let weight = Self.ease((time - event.end - 0.25 * 1.3 - 0.06 * 1.3 * Double(index)) / (0.84 * 1.3))
                    return CloudWindowState(rectangle: rectangle(index, at: time), before: staged[index], after: event.following[index], weight: weight)
                }
                break
            }
            sources = event.following
        }
        if windows.isEmpty {
            windows = (0..<7).map { CloudWindowState(rectangle: rectangle($0, at: time), before: sources[$0], after: sources[$0], weight: 0) }
        }
        return CloudSceneFrame(background: background, windows: windows, takeoverTarget: active?.target,
                               coverage: active.map { coverage($0, at: time) } ?? [],
                               luts: Self.lut(at: time, inner: false) + Self.lut(at: time, inner: true))
    }

    func snapshot(at seconds: Double) -> [String: Any] {
        let value = frame(at: seconds)
        func array(_ rectangle: SIMD4<Double>) -> [Double] { [rectangle.x, rectangle.y, rectangle.z, rectangle.w] }
        return ["background": value.background,
                "windows": value.windows.map { ["rectangle": array($0.rectangle), "before": $0.before, "after": $0.after, "weight": $0.weight] as [String: Any] },
                "takeoverTarget": value.takeoverTarget.map { $0 as Any } ?? NSNull(),
                "coverage": value.coverage.map(array),
                "luts": value.luts.map { [Int($0.x), Int($0.y), Int($0.z)] }]
    }
}
