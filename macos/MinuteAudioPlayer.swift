import AVFoundation

// All saver views in one host share one output; the last active view releases it.
final class MinuteAudioPlayer {
    private(set) static var sharedPlayer: AVAudioPlayer?
    private static var owners = Set<UUID>()
    private static var scheduledStart = 0.0
    private static var lastCheck = 0.0
    private(set) static var synchronizationCount = 0
    private let id = UUID()
    private let bundle: Bundle
    private(set) static var isMuted = false
    private var active = false

    init(bundle: Bundle, muted: Bool = false) {
        self.bundle = bundle
        if muted { Self.isMuted = true; Self.sharedPlayer?.volume = 0 }
    }

    var phase: Double? {
        guard active, let player = Self.sharedPlayer,
              player.deviceCurrentTime >= Self.scheduledStart, player.isPlaying else { return nil }
        return ClockState.wrap(player.currentTime, 60)
    }
    var isPlaying: Bool { active && (Self.sharedPlayer?.isPlaying ?? false) }
    static var ownerCount: Int { owners.count }

    func toggleMuted() {
        Self.isMuted.toggle()
        Self.sharedPlayer?.volume = Self.isMuted ? 0 : 1
    }

    func start() throws {
        guard !active else { return }
        if Self.sharedPlayer == nil {
            guard let url = bundle.url(forResource: "ClockMinute", withExtension: "wav") else {
                throw NSError(domain: "CoolClockAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: "ClockMinute.wav is missing"])
            }
            let player = try AVAudioPlayer(contentsOf: url)
            guard abs(player.duration - 60) < 1 / 44100.0, player.numberOfChannels == 2 else {
                throw NSError(domain: "CoolClockAudio", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected a 60-second stereo audio loop"])
            }
            player.numberOfLoops = -1
            player.volume = Self.isMuted ? 0 : 1
            Self.sharedPlayer = player
            do { try Self.synchronize() } catch {
                player.stop()
                Self.sharedPlayer = nil
                throw error
            }
        }
        Self.owners.insert(id)
        active = true
    }

    private static func synchronize() throws {
        guard let player = sharedPlayer else { return }
        player.stop()
        guard player.prepareToPlay() else { throw NSError(domain: "CoolClockAudio", code: 3) }
        let delay = 0.1
        scheduledStart = player.deviceCurrentTime + delay
        player.currentTime = ClockState.wrap(ClockState.localTime() + delay, 60)
        guard player.play(atTime: scheduledStart) else { throw NSError(domain: "CoolClockAudio", code: 4) }
        lastCheck = ProcessInfo.processInfo.systemUptime
        synchronizationCount += 1
    }

    // Only a clock change, sleep or interruption warrants a new seek, never ordinary drift.
    func recoverIfNeeded() throws {
        guard active, let player = Self.sharedPlayer else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - Self.lastCheck >= 1, player.deviceCurrentTime > Self.scheduledStart + 0.2 else { return }
        Self.lastCheck = now
        let error = ClockState.wrap(player.currentTime - ClockState.localTime() + 30, 60) - 30
        if !player.isPlaying || abs(error) > 0.5 { try Self.synchronize() }
    }

    func stop() {
        guard active else { return }
        active = false
        Self.owners.remove(id)
        if Self.owners.isEmpty {
            Self.sharedPlayer?.stop()
            Self.sharedPlayer = nil
        }
    }

    deinit { stop() }
}
