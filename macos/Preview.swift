import AppKit
import ScreenSaver
import AVFoundation
import MetalKit
import CoreVideo
import Darwin

@main
final class PreviewApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var saver: ScreenSaverView?
    private var timer: Timer?

    static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--benchmark"), index + 1 < CommandLine.arguments.count {
            do { try benchmark(path: CommandLine.arguments[index + 1]); exit(0) }
            catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--self-test") {
            do { try selfTest(); print("PASS: .saver video readiness/phase/continuous-play/stop/restart/resize, 60fps cloud asset, vector dial and live time"); exit(0) }
            catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
            do { try renderPreview(path: CommandLine.arguments[index + 1]); exit(0) }
            catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        }
        let app = NSApplication.shared
        let delegate = PreviewApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Cool Clock")
        let settings = NSMenuItem(title: "Настройки…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        applicationMenu.addItem(settings)
        applicationMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Завершить Cool Clock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        applicationMenu.addItem(quit)
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Окно")
        windowMenu.addItem(NSMenuItem(title: "Закрыть", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 984, height: 718), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Cool Clock — предпросмотр заставки"
        window.center()
        window.delegate = self
        guard let bundle = Bundle(url: Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/Cool Clock.saver")),
              let saverClass = bundle.principalClass as? ScreenSaverView.Type,
              let saver = saverClass.init(frame: window.contentView!.bounds, isPreview: false) else {
            NSLog("Unable to load bundled Cool Clock.saver principal class")
            NSApp.terminate(nil)
            return
        }
        saver.autoresizingMask = [.width, .height]
        window.contentView = saver
        self.saver = saver
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updatePlayback()
    }

    private func updatePlayback() {
        guard let window, let saver else { return }
        let visible = window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
        if visible {
            guard timer == nil else { return }
            saver.startAnimation()
            // The system supplies this dial tick for .saver; its preview host supplies it here.
            timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak saver] _ in saver?.animateOneFrame() }
        } else {
            timer?.invalidate(); timer = nil
            saver.stopAnimation()
        }
    }

    func windowDidMiniaturize(_ notification: Notification) { updatePlayback() }
    func windowDidDeminiaturize(_ notification: Notification) { updatePlayback() }
    func windowDidChangeOcclusionState(_ notification: Notification) { updatePlayback() }

    func applicationDidBecomeActive(_ notification: Notification) {
        let reload = NSSelectorFromString("reloadAudioPreferences")
        if saver?.responds(to: reload) == true { saver?.perform(reload) }
    }

    @objc private func showSettings() {
        guard let window, window.attachedSheet == nil, let saver,
              saver.hasConfigureSheet, let sheet = saver.configureSheet else { return }
        window.beginSheet(sheet)
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        saver?.stopAnimation()
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        saver?.stopAnimation()
    }

    private static func selfTest() throws {
        let preferences = ScreenSaverDefaults(forModuleWithName: ClockPreferences.moduleName)!
        let previousSound = preferences.object(forKey: ClockPreferences.soundKey)
        let previousInstallation = preferences.object(forKey: "InstalledChoiceID")
        defer {
            if let previousSound { preferences.set(previousSound, forKey: ClockPreferences.soundKey) }
            else { preferences.removeObject(forKey: ClockPreferences.soundKey) }
            preferences.set(previousInstallation, forKey: "InstalledChoiceID")
            preferences.synchronize()
        }
        func check(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain: "CoolClockTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func waitFor(_ message: String, _ predicate: () -> Bool) throws {
            let deadline = Date().addingTimeInterval(8)
            while !predicate() {
                try check(Date() < deadline, message)
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
        }
        let state = ClockState(8 * 3600 + 58 * 60 + 22.12)
        try check(state.elapsed == 22 && state.remaining == 38, "reference counters")
        func secondTick(_ time: Double, audioPhase: Double? = nil) -> Double {
            ClockState(time, audioPhase: audioPhase).secondAngle / (.pi * 2) * 60
        }
        for onset in [55.180, 56.182, 57.185, 58.187, 59.190] {
            try check(abs(secondTick(onset - 0.001) - (floor(onset) - 1)) < 1e-9, "second hand waits for measured tone onset")
            try check(abs(secondTick(onset + 0.001) - floor(onset)) < 1e-9, "second hand advances after measured tone onset")
        }
        try check(abs(secondTick(0.133) - 59) < 1e-9, "minute boundary holds second hand until tone")
        for phase in [0.135, 0.5, 0.609, 0.999] {
            try check(abs(secondTick(phase)) < 1e-9, "minute tone produces exactly one step to zero")
        }
        try check(abs(secondTick(1) - 1) < 1e-9, "ordinary second advances at one")
        try check(abs(secondTick(59.9, audioPhase: 0.2)) < 1e-9, "second hand follows audio playback phase")
        try check(ClockState(59.9, audioPhase: 0.2).elapsed == 59, "audio phase leaves wall-clock counters unchanged")
        try check(CloudVideoTiming.phase(0) == 0 && CloudVideoTiming.phase(25) == 25, "movie anchor")
        try check(CloudVideoTiming.phase(60) == 60, "background does not restart at the clock minute")
        try check(CloudVideoTiming.phase(CloudVideoTiming.duration) == 0, "phase repeats at the movie boundary")
        try check(abs(CloudVideoTiming.error(actual: CloudVideoTiming.duration - 0.01, localSeconds: 0)) < 0.02, "phase error wraps at movie boundary")
        for index in 0..<60 {
            for radius in stride(from: 112.0, through: 280.0, by: 8.0) {
                for time in [0.0, 2.2, 3.1, 5.2, 7.9] {
                    let alpha = MinuteMarks.opacity(index: index, radius: radius, seconds: time)
                    try check(alpha >= 0 && alpha <= 0.9, "minute mark opacity bounds")
                    try check(abs(alpha - MinuteMarks.opacity(index: index, radius: radius, seconds: time + 8)) < 1e-12, "minute mark eight-second period")
                }
            }
        }
        try check(MinuteMarks.opacity(index: 0, radius: 174, seconds: 1.8) > MinuteMarks.opacity(index: 0, radius: 186, seconds: 1.8), "glint starts inward")
        try check(MinuteMarks.opacity(index: 0, radius: 186, seconds: 2.6) > MinuteMarks.opacity(index: 0, radius: 174, seconds: 2.6), "glint moves outward")
        let glowPeak = MinuteMarks.highlights(seconds: 2.2)[0]
        try check(glowPeak.index == 0 && glowPeak.radius == 180 && glowPeak.strength == 1, "halo follows the recorded glint peak")
        for time in stride(from: 0.0, through: 8.0, by: 0.1) {
            for (light, repeated) in zip(MinuteMarks.highlights(seconds: time), MinuteMarks.highlights(seconds: time + 8)) {
                try check(light.strength >= 0 && light.strength <= 1, "halo strength bounds")
                try check(abs(light.strength - repeated.strength) < 1e-12 && abs(light.radius - repeated.radius) < 1e-10, "halo repeats with the existing glint")
            }
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        guard let bundle = Bundle(url: Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/Cool Clock.saver")),
              let saverClass = bundle.principalClass as? ScreenSaverView.Type,
              let saver = saverClass.init(frame: NSRect(x: 0, y: 0, width: 400, height: 300), isPreview: false) else {
            throw NSError(domain: "CoolClockTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Compiled .saver failed to load"])
        }
        try check(saver.value(forKey: "initializationError") == nil, "compiled .saver initialized its resources")
        try check(saver.hasConfigureSheet && saver.configureSheet != nil, "compiled saver exposes native sound settings")
        let audio = MinuteAudioPlayer(bundle: bundle, muted: true)
        let secondAudio = MinuteAudioPlayer(bundle: bundle, muted: true)
        defer { audio.stop(); secondAudio.stop() }
        try audio.start()
        try waitFor("minute audio starts") { audio.phase != nil }
        let audioPlayer = MinuteAudioPlayer.sharedPlayer!
        try check(audioPlayer.numberOfLoops == -1 && audioPlayer.volume == 0, "silent test uses infinite audio loop")
        try check(abs(ClockState.wrap(audio.phase! - ClockState.localTime() + 30, 60) - 30) < 0.08, "audio starts on local minute phase")
        let audioSyncs = MinuteAudioPlayer.synchronizationCount
        try secondAudio.start()
        try check(MinuteAudioPlayer.ownerCount == 2 && MinuteAudioPlayer.sharedPlayer === audioPlayer && MinuteAudioPlayer.synchronizationCount == audioSyncs, "multiple views share one audio output without restarting it")
        audio.stop()
        try check(secondAudio.isPlaying && MinuteAudioPlayer.ownerCount == 1, "stopping one view preserves remaining audio owner")
        audioPlayer.currentTime = 59.8
        try waitFor("minute audio loops across 60 seconds") { secondAudio.phase.map { $0 < 1 } ?? false }
        try check(secondAudio.isPlaying, "audio continues after loop boundary")
        secondAudio.stop()
        try check(!audioPlayer.isPlaying && MinuteAudioPlayer.sharedPlayer == nil && MinuteAudioPlayer.ownerCount == 0, "last owner stops and releases audio")
        try audio.start()
        try waitFor("minute audio restarts") { audio.phase != nil }
        try check(abs(ClockState.wrap(audio.phase! - ClockState.localTime() + 30, 60) - 30) < 0.08, "restarted audio follows local minute")
        let continuousAudioSyncs = MinuteAudioPlayer.synchronizationCount
        let audioUntil = Date().addingTimeInterval(1.2)
        while Date() < audioUntil {
            try audio.recoverIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        try check(audio.isPlaying && MinuteAudioPlayer.synchronizationCount == continuousAudioSyncs, "ordinary audio playback never seeks")
        let mutedPhase = audio.phase!
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        try check(MinuteAudioPlayer.sharedPlayer?.volume == 0, "muted audio volume is zero")
        try check(ClockState.wrap(audio.phase! - mutedPhase, 60) > 0.08, "muted audio phase continues")
        audio.toggleMuted()
        try check(MinuteAudioPlayer.sharedPlayer?.volume == 1 && MinuteAudioPlayer.synchronizationCount == continuousAudioSyncs, "unmute changes only volume, without seek or restart")
        audio.toggleMuted()
        try check(MinuteAudioPlayer.sharedPlayer?.volume == 0, "mute restores zero volume")
        audio.stop()
        print("Minute audio: phase, shared ownership, loop, stop/restart and continuous playback passed (muted)")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        saver.autoresizingMask = [.width, .height]
        window.contentView = saver
        window.title = "Cool Clock — проверка воспроизведения"
        window.center()
        window.orderFront(nil)
        defer { saver.stopAnimation(); window.orderOut(nil) }
        func phaseError() -> Double { saver.value(forKey: "playbackPhaseError") as? Double ?? .infinity }
        func rate() -> Double { saver.value(forKey: "playbackRate") as? Double ?? 0 }
        func saverAudioPhase() -> Double { saver.value(forKey: "audioPlaybackPhase") as? Double ?? .nan }
        func sourcePhasesMatch() -> Bool {
            let phases = saver.value(forKey:"backgroundStreamPhases") as? [Double] ?? []
            let scene = saver.value(forKey:"playbackTime") as? Double ?? .nan
            return phases.count == 3 && zip(phases,[0.0,7,13]).allSatisfy { actual, offset in
                actual.isFinite && abs(ClockState.wrap(actual-scene-offset+14.5,29)-14.5) < 0.05
            }
        }
        saver.startAnimation()
        try check(saver.isAnimating, "startAnimation")
        try waitFor("60fps video must display and synchronize within 40ms") {
            saver.animateOneFrame()
            return saver.value(forKey: "videoReady") as? Bool == true && rate() == 1 && abs(phaseError()) <= 0.04 && sourcePhasesMatch()
        }
        print("Initial phase error: \(phaseError()) seconds")
        try waitFor("compiled saver must start the bundled minute audio") { saverAudioPhase().isFinite }
        let initialAudioError = ClockState.wrap(saverAudioPhase() - ClockState.localTime() + 30, 60) - 30
        try check(abs(initialAudioError) < 0.08 && saver.value(forKey: "audioInitializationError") == nil, "compiled saver audio phase and resources")
        print("Compiled saver audio phase error: \(initialAudioError) seconds")
        guard let button = saver.subviews.compactMap({ $0 as? NSButton }).first else {
            throw NSError(domain: "CoolClockTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Dial audio button is missing"])
        }
        try check(button.isTransparent && button.isAccessibilityElement(), "dial exposes a transparent accessible button")
        let muteBefore = saver.value(forKey: "isAudioMuted") as? Bool
        try check(button.accessibilityLabel() == (muteBefore == true ? "Включить звук" : "Выключить звук"), "audio button exposes its initial action")
        let audioSyncBefore = saver.value(forKey: "audioSynchronizationCount") as? Int
        button.performClick(nil)
        let muteAfter = saver.value(forKey: "isAudioMuted") as? Bool
        try check(muteAfter != muteBefore && (saver.value(forKey: "audioVolume") as? Double) == (muteAfter == true ? 0 : 1), "compiled dial click toggles actual audio volume")
        let clickPhase = saverAudioPhase()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        try check(ClockState.wrap(saverAudioPhase() - clickPhase, 60) > 0.08, "dial click preserves advancing audio phase")
        try check(button.toolTip?.contains(muteAfter == true ? "выключен" : "включён") == true, "dial tooltip reflects sound state")
        button.performClick(nil)
        try check((saver.value(forKey: "isAudioMuted") as? Bool) == muteBefore && (saver.value(forKey: "audioSynchronizationCount") as? Int) == audioSyncBefore, "second click restores sound without resynchronizing")
        try check(button.accessibilityLabel() == (muteBefore == true ? "Включить звук" : "Выключить звук"), "audio button exposes its current action")
        let savedSound = ClockPreferences.soundEnabled()
        let sheet = saver.configureSheet!
        let controls = sheet.contentView!.subviews.compactMap { $0 as? NSButton }
        guard let checkbox = controls.first(where: { $0.accessibilityIdentifier() == "soundEnabled" }),
              let cancel = controls.first(where: { $0.title == "Отмена" }),
              let save = controls.first(where: { $0.title == "Сохранить" }) else {
            throw NSError(domain: "CoolClockTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Native settings controls missing"])
        }
        window.beginSheet(sheet)
        checkbox.state = savedSound ? .off : .on
        cancel.performClick(nil)
        try check(ClockPreferences.soundEnabled() == savedSound && window.attachedSheet == nil, "Cancel closes settings without persisting edits")
        window.beginSheet(saver.configureSheet!)
        try check((checkbox.state == .on) == savedSound, "Reopening settings reloads saved sound")
        checkbox.state = savedSound ? .off : .on
        save.performClick(nil)
        try check(ClockPreferences.soundEnabled() != savedSound && (saver.value(forKey: "isAudioMuted") as? Bool) == savedSound, "Save persists and applies sound")
        try check(window.attachedSheet == nil && (saver.value(forKey: "audioSynchronizationCount") as? Int) == audioSyncBefore, "Save closes settings without restarting audio")
        window.beginSheet(saver.configureSheet!)
        checkbox.state = savedSound ? .on : .off
        save.performClick(nil)
        print("Sound settings: initial accessibility, Save, Cancel, reopen and continuous audio passed")
        let synchronizations = saver.value(forKey: "synchronizationCount") as? Int
        let continuousUntil = Date().addingTimeInterval(4.2)
        while Date() < continuousUntil {
            saver.animateOneFrame()
            try check(rate() == 1, "continuous playback must not pause for clock synchronization")
            try check((saver.value(forKey: "synchronizationCount") as? Int) == synchronizations, "continuous playback must not seek again")
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        print("Continuous playback: 4.2 seconds, no extra synchronization or pause")
        try check(sourcePhasesMatch(), "all three actual video phases remain aligned with scene")
        window.setContentSize(NSSize(width: 844, height: 390))
        saver.layoutSubtreeIfNeeded()
        saver.animateOneFrame()
        try check(saver.bounds.size == NSSize(width: 844, height: 390), "saver resized to 844×390")
        try check(button.frame == saver.bounds, "audio button follows resized clock")
        try check(saver.subviews.compactMap { $0 as? MTKView }.first?.frame == saver.bounds, "Metal fills entire wide window")
        saver.stopAnimation()
        let before = saver.value(forKey: "submittedFrames") as? Int
        saver.animateOneFrame()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        try check(!saver.isAnimating && rate() == 0 && (saver.value(forKey: "submittedFrames") as? Int) == before, "stop pauses video and ignores late frames")
        try check(!saverAudioPhase().isFinite, "compiled saver stops audio")
        saver.startAnimation()
        try waitFor("resumed video must resynchronize") {
            saver.animateOneFrame()
            return rate() == 1 && abs(phaseError()) <= 0.04 && sourcePhasesMatch()
        }
        print("Resumed phase error: \(phaseError()) seconds")
        try waitFor("compiled saver audio resumes on the local minute") {
            saverAudioPhase().isFinite && abs(ClockState.wrap(saverAudioPhase() - ClockState.localTime() + 30, 60) - 30) < 0.08
        }
        saver.stopAnimation()
        saver.startAnimation()
        saver.stopAnimation()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        try check(rate() == 0, "late seek/preroll callbacks cannot restart a stopped player")
        try check(!saverAudioPhase().isFinite, "rapid start/stop leaves compiled saver audio stopped")
        try check(saver.value(forKey: "initializationError") == nil, "validated two silent29-second1968×1436 60fps assets")
        let glyphs = try ClockGlyphs(bundle: bundle)
        try check(glyphs.paths.count == 10 && glyphs.paths.values.allSatisfy { !$0.isEmpty }, "all vector glyphs")
        let previewHost = PreviewApp()
        previewHost.window = window; previewHost.saver = saver
        window.orderOut(nil)
        previewHost.updatePlayback()
        try check(previewHost.timer == nil && !saver.isAnimating && rate() == 0, "hidden preview stops timer and all video streams")
        window.orderFront(nil)
        try waitFor("visible preview resumes synchronized playback") {
            previewHost.updatePlayback()
            return previewHost.timer != nil && rate() == 1 && sourcePhasesMatch()
        }
        window.orderOut(nil)
        previewHost.updatePlayback()
        try check(previewHost.timer == nil && rate() == 0 && !saverAudioPhase().isFinite, "hiding preview again releases audio and pauses playback")
        window.orderFront(nil)
        let video = try CloudVideoPlayer(bundle: bundle)
        window.contentView = video.view
        try waitFor("all three source players prepare") { video.streamLoopCounts.count == 3 }
        for (index, offset) in [0.0, 7, 13].enumerated() {
            let loops = video.streamLoopCounts
            video.start(atSceneTime: 29 - offset - 0.3)
            try waitFor("source\(index) must render across its29-second loop") {
                video.view.draw()
                return video.isReady && video.streamLoopCounts[index] > loops[index]
            }
            let framesAtBoundary = video.streamFrameCounts[index]
            try waitFor("source\(index) supplies fresh frames after the loop") {
                video.view.draw()
                return video.streamFrameCounts[index] >= framesAtBoundary + 4
            }
            try check(video.streamPhases[index] < 2, "source\(index) returns to its beginning")
            for (actual, phaseOffset) in zip(video.streamPhases,[0.0,7,13]) {
                try check(abs(ClockState.wrap(actual-video.playbackTime-phaseOffset+14.5,29)-14.5) < 0.05, "actual source phase matches scene across loop")
            }
            try check(video.error == nil, "source loop retains usable textures")
            video.stop()
        }
        for size in [NSSize(width:844,height:390), NSSize(width:390,height:844)] {
            window.setContentSize(size)
            window.contentView?.layoutSubtreeIfNeeded()
            try check(video.view.bounds.size == size, "Metal background fills resized window")
        }
        print("Three staggered source loops and wide/portrait Metal layout passed")
    }

    private static func renderPreview(path: String) throws {
        _ = NSApplication.shared
        guard let bundle = Bundle(url: Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/Cool Clock.saver")) else { throw NSError(domain: "CoolClock", code: 40) }
        let width = Int(argument("--width") ?? "984") ?? 984
        let height = Int(argument("--height") ?? "718") ?? 718
        guard width > 0, height > 0, width <= 8192, height <= 8192 else { throw NSError(domain:"CoolClock",code:43) }
        let timeIndex = CommandLine.arguments.firstIndex(of: "--time")
        let time = timeIndex.flatMap { $0 + 1 < CommandLine.arguments.count ? Double(CommandLine.arguments[$0 + 1]) : nil } ?? 0
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { throw NSError(domain: "CoolClock", code: 20) }
        if !CommandLine.arguments.contains("--dial-only") {
            let image = try backgroundImage(bundle: bundle, seconds: time, width: width, height: height)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        if !CommandLine.arguments.contains("--background-only") {
            let face = ClockFaceView(frame: .zero, glyphs: try ClockGlyphs(bundle: bundle))
            face.render(in: context, size: CGSize(width: width, height: height), time: 8 * 3600 + 58 * 60 + 22.12 + time, animation: time, referenceAnimation: true)
        }
        guard let result = context.makeImage(), let png = NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:]) else { throw NSError(domain: "CoolClock", code: 21) }
        try png.write(to: URL(fileURLWithPath: path))
        print("Rendered \(path)")
    }

    private static func argument(_ name: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: name), index + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[index + 1]
    }

    // Offline export only: production retains GPU textures and never reads pixels back.
    private static func backgroundImage(bundle: Bundle, seconds: Double, width: Int, height: Int) throws -> CGImage {
        func failure(_ code: Int) -> NSError { NSError(domain: "CoolClockExport", code: code) }
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw failure(1) }
        let renderer = try CloudRenderer(device: device, bundle: bundle)
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil,nil,device,nil,&cache) == kCVReturnSuccess, let cache else { throw failure(2) }
        var buffers: [CVPixelBuffer] = [], wrappers: [CVMetalTexture] = [], textures: [MTLTexture] = []
        for (name, offset) in [("CloudSwift",0.0),("CloudCirrus",7.0),("CloudSwift",13.0)] {
            guard let url = bundle.url(forResource:name,withExtension:"mp4") else { throw failure(3) }
            let asset = AVURLAsset(url:url)
            guard let track = asset.tracks(withMediaType:.video).first else { throw failure(4) }
            let reader = try AVAssetReader(asset:asset)
            let output = AVAssetReaderTrackOutput(track:track,outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,kCVPixelBufferMetalCompatibilityKey as String:true])
            output.alwaysCopiesSampleData = false
            reader.add(output)
            let frame = Int(floor(ClockState.wrap(seconds + offset,29) * 60 + 1e-7))
            reader.timeRange = CMTimeRange(start:CMTime(value:Int64(frame),timescale:60),duration:CMTime(value:1,timescale:60))
            guard reader.startReading(), let sample = output.copyNextSampleBuffer(), let buffer = CMSampleBufferGetImageBuffer(sample) else { throw reader.error ?? failure(5) }
            var wrapper: CVMetalTexture?
            let status = CVMetalTextureCacheCreateTextureFromImage(nil,cache,buffer,nil,.r8Unorm,CVPixelBufferGetWidthOfPlane(buffer,0),CVPixelBufferGetHeightOfPlane(buffer,0),0,&wrapper)
            guard status == kCVReturnSuccess, let wrapper, let texture = CVMetalTextureGetTexture(wrapper) else { throw failure(6) }
            buffers.append(buffer); wrappers.append(wrapper); textures.append(texture)
            reader.cancelReading()
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:width,height:height,mipmapped:false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor:descriptor), let command = queue.makeCommandBuffer() else { throw failure(7) }
        try renderer.encode(commandBuffer:command,target:target,textures:textures,seconds:seconds)
        command.commit(); command.waitUntilCompleted()
        guard command.status == .completed else { throw command.error ?? failure(8) }
        var bytes = [UInt8](repeating:0,count:width*height*4)
        target.getBytes(&bytes,bytesPerRow:width*4,from:MTLRegionMake2D(0,0,width,height),mipmapLevel:0)
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(data:&bytes,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:info), let image = context.makeImage() else { throw failure(9) }
        withExtendedLifetime((buffers,wrappers)) {}
        return image
    }

    private static func benchmark(path: String) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let bundleURL = argument("--bundle").map { URL(fileURLWithPath:$0) } ?? Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/Cool Clock.saver")
        guard let bundle = Bundle(url:bundleURL), let type = bundle.principalClass as? ScreenSaverView.Type,
              let saver = type.init(frame:NSRect(x:0,y:0,width:984,height:718),isPreview:true) else { throw NSError(domain:"CoolClockBenchmark",code:1) }
        let window = NSWindow(contentRect:saver.bounds,styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false
        window.title = "Cool Clock — измерение нагрузки"
        window.contentView = saver; window.center(); window.orderFront(nil)
        defer { saver.stopAnimation(); window.orderOut(nil) }
        let timer = Timer.scheduledTimer(withTimeInterval:1/30,repeats:true) { _ in saver.animateOneFrame(); saver.displayIfNeeded() }
        defer { timer.invalidate() }
        saver.startAnimation()
        let deadline = Date().addingTimeInterval(12)
        while saver.value(forKey:"videoReady") as? Bool != true || saver.value(forKey:"playbackRate") as? Double != 1 {
            guard Date() < deadline, saver.value(forKey:"initializationError") == nil else { throw NSError(domain:"CoolClockBenchmark",code:2) }
            RunLoop.current.run(until:Date().addingTimeInterval(0.01))
        }
        RunLoop.current.run(until:Date().addingTimeInterval(2))
        func usage() -> (Double,Int64) {
            var value = rusage(); getrusage(RUSAGE_SELF,&value)
            return (Double(value.ru_utime.tv_sec+value.ru_stime.tv_sec)+Double(value.ru_utime.tv_usec+value.ru_stime.tv_usec)/1e6,Int64(value.ru_maxrss))
        }
        let metrics = ["renderedBackgroundFrames","missingBackgroundFrames","busyBackgroundFrames","staleBackgroundFrames","backgroundGPUMilliseconds","backgroundGPUFrames"]
        func sample() -> [String:Double] {
            var result:[String:Double] = [:]
            for key in metrics where saver.responds(to:NSSelectorFromString(key)) { result[key] = (saver.value(forKey:key) as? NSNumber)?.doubleValue ?? 0 }
            return result
        }
        let initialStreamFrames = saver.responds(to:NSSelectorFromString("backgroundStreamFrames")) ? saver.value(forKey:"backgroundStreamFrames") as? [Int] : nil
        let initialStreamLoops = saver.responds(to:NSSelectorFromString("backgroundStreamLoops")) ? saver.value(forKey:"backgroundStreamLoops") as? [Int] : nil
        let initialHolds = saver.responds(to:NSSelectorFromString("backgroundHeldSamples")) ? saver.value(forKey:"backgroundHeldSamples") as? [Int] : nil
        let initialSkips = saver.responds(to:NSSelectorFromString("backgroundSkippedFrames")) ? saver.value(forKey:"backgroundSkippedFrames") as? [Int] : nil
        if saver.responds(to:NSSelectorFromString("resetBackgroundTimingDiagnostics")) { saver.perform(NSSelectorFromString("resetBackgroundTimingDiagnostics")) }
        let initialSynchronizations = saver.value(forKey:"synchronizationCount") as? Int
        let before = usage(), first = sample(), started = CACurrentMediaTime()
        let duration = max(5,min(60,Double(argument("--seconds") ?? "20") ?? 20))
        RunLoop.current.run(until:Date().addingTimeInterval(duration))
        let elapsed = CACurrentMediaTime()-started, after = usage(), last = sample()
        var report:[String:Any] = ["bundle":bundleURL.path,"version":bundle.object(forInfoDictionaryKey:"CFBundleShortVersionString") ?? "unknown","elapsed_seconds":elapsed,"cpu_percent_one_core":100*(after.0-before.0)/elapsed,"peak_rss_bytes":after.1,"content_size":[984,718],"backing_scale":window.backingScaleFactor,"limits":"Actual saver in visible benchmark host,30fps dial; processCPU/RSS only, not totalGPU memory or power"]
        for (key,value) in last { report[key] = value-(first[key] ?? 0) }
        if saver.responds(to:NSSelectorFromString("backgroundStreamFrames")) {
            let frames = saver.value(forKey:"backgroundStreamFrames") as? [Int] ?? []
            let loops = saver.value(forKey:"backgroundStreamLoops") as? [Int] ?? []
            let deltas = zip(frames,initialStreamFrames ?? []).map { $0.0 - $0.1 }
            let loopDeltas = zip(loops,initialStreamLoops ?? []).map { $0.0 - $0.1 }
            report["stream_frames"] = deltas
            report["stream_loops"] = loopDeltas
            report["maximum_frame_age_seconds"] = saver.value(forKey:"maximumBackgroundFrameAge")
            let holds = saver.value(forKey:"backgroundHeldSamples") as? [Int] ?? []
            let skips = saver.value(forKey:"backgroundSkippedFrames") as? [Int] ?? []
            report["stream_held_samples"] = zip(holds,initialHolds ?? []).map { $0.0 - $0.1 }
            report["stream_skipped_frames"] = zip(skips,initialSkips ?? []).map { $0.0 - $0.1 }
            report["stream_maximum_pts_delay_seconds"] = saver.value(forKey:"backgroundMaximumPTSDelay")
            report["stream_maximum_pts_increment_seconds"] = saver.value(forKey:"backgroundMaximumPTSIncrement")
            let rendered = last["renderedBackgroundFrames",default:0]-first["renderedBackgroundFrames",default:0]
            let smooth = rendered >= elapsed*59 && deltas.count == 3 && deltas.allSatisfy { Double($0) >= rendered*0.99 }
            report["frame_pacing_passed"] = smooth
            report["source_loop_coverage_passed"] = duration < 29 || (loopDeltas.count == 3 && loopDeltas.allSatisfy { $0 > 0 })
        }
        report["continuous_without_resynchronizing"] = initialSynchronizations == saver.value(forKey:"synchronizationCount") as? Int
        guard saver.value(forKey:"initializationError") == nil, saver.value(forKey:"playbackRate") as? Double == 1 else { throw NSError(domain:"CoolClockBenchmark",code:3) }
        let data = try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:URL(fileURLWithPath:path))
        print(String(data:data,encoding:.utf8)!)
    }
}
