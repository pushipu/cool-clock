import AppKit

struct ClockState {
    let seconds: Double
    let elapsed: Int
    let remaining: Int
    let hourAngle: Double
    let minuteAngle: Double
    let secondAngle: Double

    init(_ secondsOfDay: Double, audioPhase: Double? = nil) {
        seconds = Self.wrap(secondsOfDay, 60)
        elapsed = Int(floor(seconds))
        remaining = (60 - elapsed) % 60
        hourAngle = Self.wrap(secondsOfDay, 43200) / 43200 * .pi * 2
        minuteAngle = Self.wrap(secondsOfDay, 3600) / 3600 * .pi * 2
        // Measured tone onsets preserve the soundtrack while correcting its recorded A/V delay.
        let phase = Self.wrap(audioPhase ?? secondsOfDay, 60)
        let tick = floor(phase)
        let onset = tick == 0 ? 0.134 : tick >= 55 ? [55.180, 56.182, 57.185, 58.187, 59.190][Int(tick) - 55] : tick
        secondAngle = Self.wrap(tick - (phase < onset ? 1 : 0), 60) / 60 * .pi * 2
    }

    static func wrap(_ value: Double, _ period: Double) -> Double {
        (value.truncatingRemainder(dividingBy: period) + period).truncatingRemainder(dividingBy: period)
    }

    static func localTime(_ date: Date = Date()) -> Double {
        let components = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        return Double(components.hour! * 3600 + components.minute! * 60 + components.second!) + Double(components.nanosecond!) / 1_000_000_000
    }
}

enum CloudVideoTiming {
    static let duration = 116.0
    static func phase(_ localSeconds: Double) -> Double { ClockState.wrap(localSeconds, duration) }
    static func error(actual: Double, localSeconds: Double) -> Double {
        ClockState.wrap(actual - phase(localSeconds) + duration / 2, duration) - duration / 2
    }
}

enum MinuteMarks {
    private static let glints: [(Int, Double, Double)] = [
        (0, 2.2, 180), (10, 3.1, 180), (15, 2.2, 180), (15, 5.2, 195),
        (20, 3.5, 180), (30, 2.2, 180), (35, 4.5, 180), (55, 3.0, 180)
    ]

    private static func highlight(peak: Double, origin: Double, seconds: Double) -> (radius: Double, strength: Double) {
        let delta = ClockState.wrap(seconds - peak + 4, 8) - 4
        return (origin + 12 * max(-1, min(1, delta / 0.8)), exp(-0.5 * pow(delta / 0.55, 2)))
    }

    static func highlights(seconds: Double) -> [(index: Int, radius: Double, strength: Double)] {
        glints.map { mark, peak, origin in
            let light = highlight(peak: peak, origin: origin, seconds: seconds)
            return (mark, light.radius, light.strength)
        }
    }

    static func opacity(index: Int, radius: Double, seconds: Double) -> Double {
        func smoothstep(_ value: Double) -> Double {
            let x = max(0, min(1, value))
            return x * x * (3 - 2 * x)
        }
        let envelope = smoothstep((radius - 112) / 68) * (1 - smoothstep((radius - 232) / 48))
        var alpha = index % 5 == 0 ? 0.19 : 0.15
        for (mark, peak, origin) in glints where index == mark {
            let light = highlight(peak: peak, origin: origin, seconds: seconds)
            alpha += 0.72 * light.strength * exp(-0.5 * pow((radius - light.radius) / 12, 2))
        }
        return envelope * min(0.9, alpha)
    }
}

struct ClockGlyphs {
    let paths: [Character: CGPath]

    init(bundle: Bundle) throws {
        guard let url = bundle.url(forResource: "Glyphs", withExtension: "json") else {
            throw NSError(domain: "CoolClock", code: 1, userInfo: [NSLocalizedDescriptionKey: "Glyphs.json is missing"])
        }
        let outlines = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
        paths = try Dictionary(uniqueKeysWithValues: outlines.map { key, value in (Character(key), try Self.parse(value)) })
        guard paths.count == 10 else { throw NSError(domain: "CoolClock", code: 2) }
    }

    // The bundled paths use only these absolute SVG commands; fail on malformed resources.
    static func parse(_ outline: String) throws -> CGPath {
        let expression = try NSRegularExpression(pattern: "[A-Za-z]|-?[0-9]+(?:\\.[0-9]+)?")
        let tokens = expression.matches(in: outline, range: NSRange(outline.startIndex..., in: outline))
            .map { (outline as NSString).substring(with: $0.range) }
        var index = 0
        var point = CGPoint.zero
        let path = CGMutablePath()
        func number() throws -> CGFloat {
            guard index < tokens.count, let value = Double(tokens[index]) else { throw NSError(domain: "CoolClock", code: 3) }
            index += 1
            return CGFloat(value)
        }
        while index < tokens.count {
            let command = tokens[index]
            index += 1
            switch command {
            case "M", "L":
                point = try CGPoint(x: number(), y: number())
                if command == "M" { path.move(to: point) } else { path.addLine(to: point) }
            case "H": point.x = try number(); path.addLine(to: point)
            case "V": point.y = try number(); path.addLine(to: point)
            case "Q":
                let control = try CGPoint(x: number(), y: number())
                point = try CGPoint(x: number(), y: number())
                path.addQuadCurve(to: point, control: control)
            case "Z": path.closeSubpath(); point = path.currentPoint
            default: throw NSError(domain: "CoolClock", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unsupported glyph command \(command)"])
            }
        }
        return path
    }

    func draw(_ text: String, at point: CGPoint, height: CGFloat, width: CGFloat, alpha: CGFloat = 1, in context: CGContext) {
        func advance(_ digit: Character) -> CGFloat { digit == "1" ? 57 : digit == "2" ? 87 : digit == "4" ? 106 : 100 }
        let gap: CGFloat = text == "11" || text == "12" ? 12 : 7
        let naturalWidth = text.reduce(CGFloat(0)) { $0 + advance($1) } + CGFloat(text.count - 1) * gap
        context.saveGState()
        context.translateBy(x: point.x - width / 2, y: point.y - height / 2)
        context.scaleBy(x: width / naturalWidth, y: height / 50)
        context.setFillColor(CGColor(red: 235 / 255, green: 243 / 255, blue: 1, alpha: alpha))
        for digit in text {
            context.saveGState()
            if digit == "2" { context.scaleBy(x: 0.87, y: 1) }
            if let path = paths[digit] { context.addPath(path); context.drawPath(using: .eoFill) }
            context.restoreGState()
            context.translateBy(x: advance(digit) + gap, y: 0)
        }
        context.restoreGState()
    }
}

final class ClockFaceView: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    let glyphs: ClockGlyphs
    var animationTime: Double = 0
    var audioPhase: Double?

    // Cache the small halo once; blurring the whole dial each frame is unnecessary.
    private static let minuteGlow: CGImage = {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: 32, height: 192, bitsPerComponent: 8,
                                bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let locations = (0...8).map { CGFloat($0) / 8 }
        let colors = locations.map { radius in
            CGColor(red: 235 / 255, green: 243 / 255, blue: 1,
                    alpha: radius == 1 ? 0 : 0.24 * exp(-5.12 * radius * radius))
        }
        let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
        context.translateBy(x: 16, y: 96)
        context.scaleBy(x: 16, y: 96)
        context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0,
                                   endCenter: .zero, endRadius: 1, options: [])
        return context.makeImage()!
    }()

    init(frame: NSRect, glyphs: ClockGlyphs) {
        self.glyphs = glyphs
        super.init(frame: frame)
        wantsLayer = true
        layer?.isOpaque = false
        autoresizingMask = [.width, .height]
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(dirtyRect)
        render(in: context, size: bounds.size, time: ClockState.localTime(), animation: animationTime, audioPhase: audioPhase)
    }

    func render(in context: CGContext, size: CGSize, time: Double, animation: Double, referenceAnimation: Bool = false, audioPhase: Double? = nil) {
        let scale = min(size.width / 984, size.height / 718)
        let state = ClockState(time, audioPhase: audioPhase)
        context.saveGState()
        context.translateBy(x: (size.width - 984 * scale) / 2, y: (size.height - 718 * scale) / 2)
        context.scaleBy(x: scale, y: scale)
        let phase = animation * (referenceAnimation ? 1 : 112 / CloudVideoTiming.duration)
        for light in MinuteMarks.highlights(seconds: phase) where light.strength >= 0.002 {
            context.saveGState()
            context.translateBy(x: 492, y: 359)
            context.scaleBy(x: 1.03, y: 1)
            context.rotate(by: Double(light.index) * .pi / 30)
            context.setAlpha(light.strength)
            context.draw(Self.minuteGlow, in: CGRect(x: -8, y: -light.radius - 48, width: 16, height: 96))
            context.restoreGState()
        }
        for index in 0..<60 {
            let angle = Double(index) * .pi / 30
            let dx = sin(angle) * 1.03, dy = -cos(angle)
            let start = CGPoint(x: 492 + dx * 112, y: 359 + dy * 112)
            let end = CGPoint(x: 492 + dx * 280, y: 359 + dy * 280)
            let radii = stride(from: 112.0, through: 280.0, by: 8.0)
            let colors = radii.map { radius in
                CGColor(red: 235 / 255, green: 243 / 255, blue: 1,
                        alpha: MinuteMarks.opacity(index: index, radius: radius, seconds: phase))
            }
            let locations = radii.map { CGFloat(($0 - 112) / 168) }
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations)!
            context.saveGState()
            context.setLineWidth(index % 5 == 0 ? 3.2 : 2.5)
            context.move(to: start)
            context.addLine(to: end)
            context.replacePathWithStrokedPath()
            context.clip()
            context.drawLinearGradient(gradient, start: start, end: end, options: [])
            context.restoreGState()
        }
        let numerals: [(Int, CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (10,202.5,185,147,46), (11,351,185,112,46), (12,496,185,138,46), (1,638.5,185,51,46), (2,777,185,78,46),
            (3,782,357.5,88,47), (4,782,534.5,100,47), (5,646,533,86,46), (6,495.5,534,91,46),
            (7,352.5,534,83,46), (8,201,533,94,46), (9,197.5,357.5,91,47)
        ]
        for (value, x, y, width, height) in numerals {
            let brightness = 0.63 + 0.30 * (0.5 + 0.5 * sin(animation * .pi * 12 / CloudVideoTiming.duration + Double(value) * 0.83))
            glyphs.draw(String(value), at: CGPoint(x: x, y: y), height: height, width: width, alpha: brightness, in: context)
        }
        drawRuler(state.seconds, reverse: false, in: context)
        drawRuler(state.seconds, reverse: true, in: context)
        let counterWidths: [CGFloat] = [34, 19, 30, 30, 34, 31, 31, 28, 32, 32]
        for (value, y) in [(state.elapsed, CGFloat(107)), (state.remaining, CGFloat(611))] {
            for (index, digit) in String(format: "%02d", value).enumerated() {
                let x = CGFloat(452 + index * 40)
                context.setFillColor(CGColor(red: 181 / 255, green: 203 / 255, blue: 238 / 255, alpha: 0.28))
                context.fill(CGRect(x: x, y: y - 17, width: 39, height: 34))
                glyphs.draw(String(digit), at: CGPoint(x: x + 20, y: y), height: 22, width: counterWidths[digit.wholeNumberValue!], in: context)
            }
        }
        for (angle, length, tail, tailWidth, tipWidth) in [(state.hourAngle, 175.5, 13.0, 15.0, 6.0), (state.minuteAngle, 194, 29, 10, 3), (state.secondAngle, 200, 30, 5.6, 1.3)] {
            context.saveGState()
            context.translateBy(x: 492, y: 359)
            context.scaleBy(x: 1.03, y: 1)
            context.rotate(by: angle)
            context.setFillColor(CGColor(red: 245 / 255, green: 249 / 255, blue: 1, alpha: 1))
            context.move(to: CGPoint(x: -tailWidth / 2, y: tail))
            context.addLine(to: CGPoint(x: tailWidth / 2, y: tail))
            context.addLine(to: CGPoint(x: tipWidth / 2, y: -length))
            context.addLine(to: CGPoint(x: -tipWidth / 2, y: -length))
            context.closePath()
            context.fillPath()
            context.restoreGState()
        }
        context.restoreGState()
    }

    private func drawRuler(_ seconds: Double, reverse: Bool, in context: CGContext) {
        let value = ClockState.wrap(reverse ? -seconds : seconds, 60)
        let center = Int(floor(value * 10))
        let baseline = reverse ? 567.0 : 150.0
        let direction = reverse ? 1.0 : -1.0
        for tick in (center - 50)...(center + 50) {
            let x = 346 * sin((Double(tick) / 10 - value) * .pi / 15)
            let fade = max(0, min(1, (abs(x) - 80) / 220))
            let alpha = 1 - fade * fade * (3 - 2 * fade)
            if alpha == 0 { continue }
            let major = tick % 10 == 0
            context.setStrokeColor(CGColor(red: 201 / 255, green: 220 / 255, blue: 1, alpha: alpha * (major ? 0.9 : 0.8)))
            context.setLineWidth(major ? 3.2 : 2.6)
            context.move(to: CGPoint(x: 492 + x, y: baseline))
            context.addLine(to: CGPoint(x: 492 + x, y: baseline + direction * (major ? 35 : 18)))
            context.strokePath()
            if tick % 50 == 0 {
                let label = Int(ClockState.wrap(Double(tick) / 10, 60))
                glyphs.draw(String(label), at: CGPoint(x: 492 + x, y: baseline + direction * 44), height: 10, width: label < 10 ? 13 : 30, alpha: alpha * 0.75, in: context)
            }
        }
    }
}
