import AppKit
import AVFoundation
import MetalKit
import CoreVideo

final class CloudVideoPlayer: NSObject, MTKViewDelegate {
    private final class DisplayClock {
        weak var owner: CloudVideoPlayer?
        private let lock = NSLock()
        private var active = false
        private var generation = 0
        private var pending = false
        private var latestHost = 0.0
        private var nextDueHost: Double?

        func activate(generation: Int) {
            lock.lock(); defer { lock.unlock() }
            self.generation = generation
            active = true
            pending = false
            nextDueHost = nil
        }

        func deactivate() {
            lock.lock(); defer { lock.unlock() }
            active = false
            pending = false
            nextDueHost = nil
        }

        func screenChanged() {
            lock.lock(); defer { lock.unlock() }
            nextDueHost = nil
        }

        func schedule(_ stamp: CVTimeStamp) {
            let host = CMClockMakeHostTimeFromSystemUnits(stamp.hostTime).seconds
            guard host.isFinite else { return }
            let refresh = stamp.videoTimeScale > 0 ? Double(stamp.videoRefreshPeriod) / Double(stamp.videoTimeScale) : 1 / 60
            lock.lock()
            guard active else { lock.unlock(); return }
            // Select the nearest screen refresh to each60Hz deadline, including120Hz displays.
            if let due = nextDueHost, host < due - refresh / 2 - 0.000001 { lock.unlock(); return }
            let period = 1.0 / 60
            let due = nextDueHost ?? host
            nextDueHost = due + max(1, floor((host - due + 0.000001) / period) + 1) * period
            assert(nextDueHost! > host)
            latestHost = host
            guard !pending else { lock.unlock(); return }
            pending = true
            let token = generation
            lock.unlock()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                guard self.active, self.generation == token else { self.lock.unlock(); return }
                let target = self.latestHost
                self.pending = false
                self.lock.unlock()
                self.owner?.draw(atHostTime: target, generation: token)
            }
        }
    }

    private struct Frame {
        let buffer: CVPixelBuffer
        let wrapper: CVMetalTexture
        let texture: MTLTexture
    }

    private final class Stream {
        let player = AVQueuePlayer()
        let offset: Double
        let looper: AVPlayerLooper
        var onChange: (() -> Void)?
        private var observations: [NSKeyValueObservation] = []
        private var itemObservation: NSKeyValueObservation?
        private var outputs: [ObjectIdentifier: (AVPlayerItem, AVPlayerItemVideoOutput)] = [:]
        var frame: Frame?
        var frameCount = 0
        var lastFrameHost: Double = 0
        var heldSamples = 0
        var skippedPTSFrames = 0
        var lastPTS = Double.nan
        var maximumPTSDelay = 0.0
        var maximumPTSIncrement = 0.0

        init(asset: AVURLAsset, offset: Double) {
            self.offset = offset
            player.isMuted = true
            player.automaticallyWaitsToMinimizeStalling = false
            player.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
            observations = [
                player.observe(\.currentItem, options: [.initial, .new]) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.observeCurrentItem() }
                },
                player.observe(\.status, options: [.new]) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.onChange?() }
                },
                looper.observe(\.status, options: [.new]) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.onChange?() }
                }
            ]
            attachQueuedOutputs()
        }

        private func attachQueuedOutputs() {
            let items = player.items()
            let identities = Set(items.map(ObjectIdentifier.init))
            outputs = outputs.filter { identities.contains($0.key) }
            for item in items where outputs[ObjectIdentifier(item)] == nil {
                if let output = item.outputs.compactMap({ $0 as? AVPlayerItemVideoOutput }).first {
                    outputs[ObjectIdentifier(item)] = (item, output)
                    continue
                }
                let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                    kCVPixelBufferMetalCompatibilityKey as String: true
                ])
                output.suppressesPlayerRendering = true
                item.add(output)
                outputs[ObjectIdentifier(item)] = (item, output)
            }
        }

        private func observeCurrentItem() {
            attachQueuedOutputs()
            itemObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.onChange?() }
            }
            onChange?()
        }

        var error: Error? {
            if player.status == .failed { return player.error ?? CloudVideoPlayer.failure(38, "Cloud player failed") }
            if looper.status == .failed { return looper.error ?? CloudVideoPlayer.failure(33, "Cloud loop failed") }
            if player.currentItem?.status == .failed { return player.currentItem?.error ?? CloudVideoPlayer.failure(34, "Cloud item failed") }
            return nil
        }

        func sample(host: Double, cache: CVMetalTextureCache) throws {
            guard let item = player.currentItem else { return }
            if outputs[ObjectIdentifier(item)] == nil { attachQueuedOutputs() }
            guard let output = outputs[ObjectIdentifier(item)]?.1 else { return }
            let time = output.itemTime(forHostTime: host)
            var displayTime = CMTime.invalid
            guard output.hasNewPixelBuffer(forItemTime: time),
                  let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: &displayTime) else {
                if frame != nil { heldSamples += 1 }
                if lastPTS.isFinite { maximumPTSDelay = max(maximumPTSDelay, ClockState.wrap(time.seconds - lastPTS + 14.5, 29) - 14.5) }
                return
            }
            let pts = displayTime.seconds
            if lastPTS.isFinite, pts.isFinite {
                let increment = ClockState.wrap(pts - lastPTS, 29)
                maximumPTSIncrement = max(maximumPTSIncrement, increment)
                if increment > 1.5 / 60, increment < 1 { skippedPTSFrames += max(0, Int((increment * 60).rounded()) - 1) }
            }
            lastPTS = pts
            if pts.isFinite { maximumPTSDelay = max(maximumPTSDelay, ClockState.wrap(time.seconds - pts + 14.5, 29) - 14.5) }
            guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                  CVPixelBufferGetPlaneCount(buffer) == 2,
                  CVPixelBufferGetWidthOfPlane(buffer, 0) == 1968,
                  CVPixelBufferGetHeightOfPlane(buffer, 0) == 1436 else {
                throw CloudVideoPlayer.failure(40, "Expected video-range NV12 cloud frames")
            }
            var wrapper: CVMetalTexture?
            let result = CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, .r8Unorm,
                CVPixelBufferGetWidthOfPlane(buffer, 0), CVPixelBufferGetHeightOfPlane(buffer, 0), 0, &wrapper)
            guard result == kCVReturnSuccess, let wrapper, let texture = CVMetalTextureGetTexture(wrapper) else {
                throw CloudVideoPlayer.failure(41, "Unable to share cloud luma with Metal (\(result))")
            }
            frame = Frame(buffer: buffer, wrapper: wrapper, texture: texture)
            frameCount += 1
            lastFrameHost = host
        }

        func stop() {
            player.cancelPendingPrerolls()
            player.currentItem?.cancelPendingSeeks()
            player.pause()
            frame = nil
            lastFrameHost = 0
            lastPTS = .nan
        }

        deinit {
            player.pause()
            player.cancelPendingPrerolls()
            looper.disableLooping()
            player.removeAllItems()
        }
    }

    let view: MTKView
    private let renderer: CloudRenderer
    private let queue: MTLCommandQueue
    private let cache: CVMetalTextureCache
    private let inFlight = DispatchSemaphore(value: 3)
    private let displayClock = DisplayClock()
    private let displayLink: CVDisplayLink
    private var screenObservation: NSObjectProtocol?
    private var scheduledHost: Double?
    private let metricsLock = NSLock()
    private var gpuTotal = 0.0
    private var gpuCount = 0
    private var streams: [Stream] = []
    private var loading: Task<Void, Never>?
    private var generation = 0
    private var running = false
    private var needsSynchronization = false
    private var synchronizing = false
    private var anchorHost: Double?
    private var anchorPhase = 0.0
    private var frozenPhase = Double.nan
    private var requestedPhase: Double?
    private var hasPresented = false
    private(set) var synchronizationCount = 0
    private(set) var renderedFrames = 0
    private(set) var lastRenderedSceneTime = Double.nan
    private(set) var missingFrames = 0
    private(set) var busyFrames = 0
    private(set) var staleFrames = 0
    private(set) var maximumFrameAge = 0.0
    private(set) var error: Error?
    var onError: ((Error) -> Void)?

    var isReady: Bool { hasPresented && error == nil && streams.count == 3 && streams.allSatisfy { $0.frame != nil } }
    var playbackTime: Double {
        guard running, let anchorHost else { return frozenPhase }
        return ClockState.wrap(anchorPhase + max(0, CACurrentMediaTime() - anchorHost), CloudVideoTiming.duration)
    }
    var playbackRate: Double { streams.map { Double($0.player.rate) }.min() ?? 0 }
    var loopCount: Int { streamLoopCounts.reduce(0, +) }
    var streamPhases: [Double] { streams.map { $0.player.currentTime().seconds } }
    var streamLoopCounts: [Int] { streams.map { $0.looper.loopCount } }
    var streamFrameCounts: [Int] { streams.map { $0.frameCount } }
    var streamHeldSamples: [Int] { streams.map { $0.heldSamples } }
    var streamSkippedPTSFrames: [Int] { streams.map { $0.skippedPTSFrames } }
    var streamMaximumPTSDelay: [Double] { streams.map { $0.maximumPTSDelay } }
    var streamMaximumPTSIncrement: [Double] { streams.map { $0.maximumPTSIncrement } }
    var gpuMillisecondsTotal: Double { metricsLock.lock(); defer { metricsLock.unlock() }; return gpuTotal }
    var gpuCompletedFrames: Int { metricsLock.lock(); defer { metricsLock.unlock() }; return gpuCount }

    init(bundle: Bundle) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw Self.failure(39, "Metal is unavailable")
        }
        self.queue = queue
        var link: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess, let link else {
            throw Self.failure(43, "Unable to create cloud display link")
        }
        displayLink = link
        renderer = try CloudRenderer(device: device, bundle: bundle)
        var cacheValue: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cacheValue) == kCVReturnSuccess, let cacheValue else {
            throw Self.failure(41, "Unable to create cloud texture cache")
        }
        cache = cacheValue
        view = MTKView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.autoResizeDrawable = true
        view.enableSetNeedsDisplay = false
        view.isPaused = true
        view.clearColor = MTLClearColor(red: 0.02, green: 0.04, blue: 0.10, alpha: 1)
        view.autoresizingMask = [.width, .height]
        super.init()
        view.delegate = self
        displayClock.owner = self
        let callbackStatus = CVDisplayLinkSetOutputCallback(displayLink, { _, _, outputTime, _, _, context in
            guard let context else { return kCVReturnError }
            Unmanaged<DisplayClock>.fromOpaque(context).takeUnretainedValue().schedule(outputTime.pointee)
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(displayClock).toOpaque())
        guard callbackStatus == kCVReturnSuccess else { throw Self.failure(43, "Unable to attach cloud display callback") }
        screenObservation = NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self, let window = notification.object as? NSWindow, window === self.view.window else { return }
            self.updateDisplay()
        }
        let assets = try ["CloudSwift", "CloudCirrus"].map { name -> AVURLAsset in
            guard let url = bundle.url(forResource: name, withExtension: "mp4") else {
                throw Self.failure(30, "\(name).mp4 is missing")
            }
            return AVURLAsset(url: url)
        }
        loading = Task { @MainActor [weak self, assets] in
            do {
                for asset in assets {
                    let (duration, tracks) = try await asset.load(.duration, .tracks)
                    let videos = tracks.filter { $0.mediaType == .video }
                    guard abs(duration.seconds - 29) < 0.02, videos.count == 1,
                          tracks.allSatisfy({ $0.mediaType != .audio }) else {
                        throw Self.failure(32, "Expected two silent 29-second cloud clips")
                    }
                    let (size, fps) = try await videos[0].load(.naturalSize, .nominalFrameRate)
                    guard abs(size.width - 1968) < 0.5, abs(size.height - 1436) < 0.5, abs(fps - 60) < 0.01 else {
                        throw Self.failure(37, "Expected cloud clips at 1968×1436, 60fps; got \(size), \(fps)fps")
                    }
                }
                guard !Task.isCancelled, let self else { return }
                self.streams = [Stream(asset: assets[0], offset: 0), Stream(asset: assets[1], offset: 7), Stream(asset: assets[0], offset: 13)]
                for stream in self.streams { stream.onChange = { [weak self] in self?.streamChanged() } }
                self.streamChanged()
            } catch {
                guard !Task.isCancelled else { return }
                self?.fail(error)
            }
        }
    }

    func start() { start(atSceneTime: nil) }

    // Explicit phase is used by the loop-boundary check, not by the normal screensaver.
    func start(atSceneTime phase: Double?) {
        guard !running, error == nil else { return }
        requestedPhase = phase.map { ClockState.wrap($0, CloudVideoTiming.duration) }
        running = true
        needsSynchronization = true
        hasPresented = false
        lastRenderedSceneTime = .nan
        synchronizeIfNeeded()
    }

    func stop() {
        frozenPhase = playbackTime
        running = false
        generation += 1
        needsSynchronization = false
        synchronizing = false
        anchorHost = nil
        scheduledHost = nil
        displayClock.deactivate()
        if CVDisplayLinkIsRunning(displayLink) { CVDisplayLinkStop(displayLink) }
        view.isPaused = true
        for stream in streams { stream.stop() }
        CVMetalTextureCacheFlush(cache, 0)
    }

    private func streamChanged() {
        if let failure = streams.compactMap({ $0.error }).first { fail(failure); return }
        synchronizeIfNeeded()
    }

    private func synchronizeIfNeeded() {
        guard running, needsSynchronization, !synchronizing, error == nil, streams.count == 3,
              streams.allSatisfy({ $0.player.currentItem?.status == .readyToPlay }) else { return }
        needsSynchronization = false
        synchronizing = true
        synchronizationCount += 1
        generation += 1
        let token = generation
        let phase = requestedPhase ?? CloudVideoTiming.phase(ClockState.localTime())
        let group = DispatchGroup()
        var succeeded = true
        for stream in streams {
            stream.player.pause()
            group.enter()
            stream.player.seek(to: CMTime(seconds: ClockState.wrap(phase + stream.offset, 29), preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                DispatchQueue.main.async { succeeded = succeeded && finished; group.leave() }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self, self.running, self.generation == token else { return }
            guard succeeded else { self.fail(Self.failure(35, "Cloud seek failed")); return }
            self.preroll(token: token)
        }
    }

    private func preroll(token: Int) {
        let group = DispatchGroup()
        var succeeded = true
        for stream in streams {
            group.enter()
            stream.player.preroll(atRate: 1) { ready in
                DispatchQueue.main.async { succeeded = succeeded && ready; group.leave() }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self, self.running, self.generation == token else { return }
            guard succeeded else { self.fail(Self.failure(36, "Cloud preroll failed")); return }
            let delay = 0.15
            let host = CACurrentMediaTime() + delay
            let phase = self.requestedPhase ?? CloudVideoTiming.phase(ClockState.localTime() + delay)
            self.anchorHost = host
            self.anchorPhase = phase
            self.frozenPhase = phase
            for stream in self.streams {
                stream.player.setRate(1,
                    time: CMTime(seconds: ClockState.wrap(phase + stream.offset, 29), preferredTimescale: 60000),
                    atHostTime: CMTime(seconds: host, preferredTimescale: 1_000_000_000))
            }
            self.synchronizing = false
            self.updateDisplay()
            guard self.error == nil else { return }
            self.displayClock.activate(generation: token)
            if CVDisplayLinkStart(self.displayLink) != kCVReturnSuccess {
                self.fail(Self.failure(43, "Unable to start cloud display link"))
            }
        }
    }

    func resetFrameTimingDiagnostics() {
        maximumFrameAge = 0
        for stream in streams {
            stream.maximumPTSDelay = 0
            stream.maximumPTSIncrement = 0
        }
    }

    private func updateDisplay() {
        guard let number = view.window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        let display = number.uint32Value
        guard display != CVDisplayLinkGetCurrentCGDisplay(displayLink) else { return }
        displayClock.screenChanged()
        if CVDisplayLinkSetCurrentCGDisplay(displayLink, display) != kCVReturnSuccess {
            fail(Self.failure(43, "Unable to move cloud display link to the window’s screen"))
        }
    }

    private func draw(atHostTime host: Double, generation token: Int) {
        guard running, generation == token else { return }
        scheduledHost = host
        view.draw()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { updateDisplay() }

    func draw(in view: MTKView) {
        guard running, !synchronizing, error == nil, let anchorHost else { return }
        guard let host = scheduledHost else { return }
        scheduledHost = nil
        guard host >= anchorHost, view.drawableSize.width > 0, view.drawableSize.height > 0 else { return }
        guard inFlight.wait(timeout: .now()) == .success else { busyFrames += 1; return }
        do {
            for stream in streams { try stream.sample(host: host, cache: cache) }
            let frames = streams.compactMap(\.frame)
            guard frames.count == 3, let drawable = view.currentDrawable, let command = queue.makeCommandBuffer() else {
                missingFrames += 1
                inFlight.signal()
                return
            }
            let age = streams.map { host - $0.lastFrameHost }.max() ?? 0
            maximumFrameAge = max(maximumFrameAge, age)
            if age > 2.5 / 60 { staleFrames += 1 }
            let time = ClockState.wrap(anchorPhase + host - anchorHost, CloudVideoTiming.duration)
            try renderer.encode(commandBuffer: command, target: drawable.texture, textures: frames.map(\.texture), seconds: time)
            let semaphore = inFlight
            command.addCompletedHandler { [weak self, frames] command in
                withExtendedLifetime(frames) {}
                semaphore.signal()
                guard let self else { return }
                self.metricsLock.lock()
                self.gpuTotal += max(0, command.gpuEndTime - command.gpuStartTime) * 1000
                self.gpuCount += 1
                self.metricsLock.unlock()
                if command.status == .error {
                    DispatchQueue.main.async { [weak self] in self?.fail(command.error ?? Self.failure(42, "Cloud rendering failed")) }
                }
            }
            command.present(drawable, atTime: host)
            command.commit()
            renderedFrames += 1
            lastRenderedSceneTime = time
            hasPresented = true
        } catch {
            inFlight.signal()
            fail(error)
        }
    }

    private static func failure(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "CoolClock", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func fail(_ error: Error) {
        guard self.error == nil else { return }
        self.error = error
        stop()
        NSLog("Cool Clock video playback failed: %@", String(describing: error))
        onError?(error)
    }

    deinit {
        loading?.cancel()
        displayClock.deactivate()
        if CVDisplayLinkIsRunning(displayLink) { CVDisplayLinkStop(displayLink) }
        if let screenObservation { NotificationCenter.default.removeObserver(screenObservation) }
        view.isPaused = true
        view.delegate = nil
        for stream in streams { stream.stop() }
    }
}
