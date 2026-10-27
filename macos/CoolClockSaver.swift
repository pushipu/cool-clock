import AppKit
import ScreenSaver
import AVFoundation

@objc(CoolClockSaverView)
final class CoolClockSaverView: ScreenSaverView {
    private var video: CloudVideoPlayer?
    private var audio: MinuteAudioPlayer?
    private var audioError: Error?
    private var faceView: ClockFaceView?
    private var audioButton: NSButton?
    private var settingsWindow: NSWindow?
    private var soundCheckbox: NSButton?
    private var settingsHint: NSTextField?
    private(set) var setupError: Error?
    private var running = false
    private var displayedMuteState: Bool?
    @objc private(set) var submittedFrames = 0
    @objc var initializationError: String? { (setupError ?? video?.error).map(String.init(describing:)) }
    @objc var isAudioMuted: Bool { audio == nil || MinuteAudioPlayer.isMuted }
    @objc var audioVolume: Double { Double(MinuteAudioPlayer.sharedPlayer?.volume ?? 0) }
    @objc var audioSynchronizationCount: Int { MinuteAudioPlayer.synchronizationCount }
    @objc var audioPlaybackPhase: Double { audio?.phase ?? .nan }
    @objc var audioInitializationError: String? { audioError.map(String.init(describing:)) }
    @objc var videoReady: Bool { video?.isReady ?? false }
    @objc var playbackRate: Double { video?.playbackRate ?? 0 }
    @objc var playbackTime: Double { video?.playbackTime ?? .nan }
    @objc var playbackPhaseError: Double { CloudVideoTiming.error(actual: playbackTime, localSeconds: ClockState.localTime()) }
    @objc var loopCount: Int { video?.loopCount ?? 0 }
    @objc var synchronizationCount: Int { video?.synchronizationCount ?? 0 }
    @objc var backgroundFrame: NSRect { video?.view.frame ?? .zero }
    @objc var renderedBackgroundFrames: Int { video?.renderedFrames ?? 0 }
    @objc var missingBackgroundFrames: Int { video?.missingFrames ?? 0 }
    @objc var busyBackgroundFrames: Int { video?.busyFrames ?? 0 }
    @objc var staleBackgroundFrames: Int { video?.staleFrames ?? 0 }
    @objc var maximumBackgroundFrameAge: Double { video?.maximumFrameAge ?? 0 }
    @objc var backgroundStreamPhases: [Double] { video?.streamPhases ?? [] }
    @objc var backgroundStreamLoops: [Int] { video?.streamLoopCounts ?? [] }
    @objc var backgroundStreamFrames: [Int] { video?.streamFrameCounts ?? [] }
    @objc var backgroundHeldSamples: [Int] { video?.streamHeldSamples ?? [] }
    @objc var backgroundSkippedFrames: [Int] { video?.streamSkippedPTSFrames ?? [] }
    @objc var backgroundMaximumPTSDelay: [Double] { video?.streamMaximumPTSDelay ?? [] }
    @objc var backgroundMaximumPTSIncrement: [Double] { video?.streamMaximumPTSIncrement ?? [] }
    @objc var backgroundGPUMilliseconds: Double { video?.gpuMillisecondsTotal ?? 0 }
    @objc var backgroundGPUFrames: Int { video?.gpuCompletedFrames ?? 0 }

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        if !isPreview {
            audio = MinuteAudioPlayer(bundle: Bundle(for: CoolClockSaverView.self))
        }
        reloadAudioPreferences()
        animationTimeInterval = 1 / 30
        wantsLayer = true
        layer?.backgroundColor = CGColor(red: 0.02, green: 0.04, blue: 0.10, alpha: 1)
        do {
            let video = try CloudVideoPlayer(bundle: Bundle(for: CoolClockSaverView.self))
            self.video = video
            video.onError = { [weak self] _ in self?.showError("Не удалось воспроизвести фон часов.") }
            video.view.frame = bounds
            video.view.autoresizingMask = [.width, .height]
            addSubview(video.view)
            let face = ClockFaceView(frame: bounds, glyphs: try ClockGlyphs(bundle: Bundle(for: CoolClockSaverView.self)))
            faceView = face
            addSubview(face)
            if audio != nil {
                let button = NSButton(frame: bounds)
                button.isTransparent = true
                button.autoresizingMask = [.width, .height]
                button.target = self
                button.action = #selector(toggleAudio(_:))
                button.setAccessibilityElement(true)
                addSubview(button)
                audioButton = button
            }
            updateAudioFeedback()
        } catch {
            setupError = error
            NSLog("Cool Clock initialization failed: %@", String(describing: error))
            showError("Cool Clock\nНе удалось загрузить видеофон.")
        }
    }
    required init?(coder: NSCoder) { nil }

    @objc func resetBackgroundTimingDiagnostics() { video?.resetFrameTimingDiagnostics() }

    deinit { audio?.stop() }

    @objc func toggleAudio(_ sender: Any?) {
        guard let audio else { return }
        let enabled = isAudioMuted
        guard ClockPreferences.setSoundEnabled(enabled) else { return }
        audio.setMuted(!enabled)
        updateAudioFeedback()
    }

    @objc func reloadAudioPreferences() {
        if !ClockPreferences.applyInstallationChoice(from: Bundle(for: CoolClockSaverView.self).bundleURL) {
            NSLog("Cool Clock could not import installation sound settings; retaining saved preferences.")
        }
        audio?.setMuted(!ClockPreferences.soundEnabled())
        updateAudioFeedback()
    }

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        if settingsWindow == nil {
            let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 220),
                                 styleMask: .titled, backing: .buffered, defer: false)
            sheet.title = "Настройки Cool Clock"
            sheet.isReleasedWhenClosed = false
            let title = NSTextField(labelWithString: "Звук заставки")
            title.font = .boldSystemFont(ofSize: 20)
            title.frame = NSRect(x: 24, y: 166, width: 430, height: 28)
            let checkbox = NSButton(checkboxWithTitle: "Воспроизводить звук", target: nil, action: nil)
            checkbox.frame = NSRect(x: 24, y: 120, width: 430, height: 24)
            checkbox.setAccessibilityIdentifier("soundEnabled")
            let hint = NSTextField(wrappingLabelWithString: "")
            hint.font = .systemFont(ofSize: 12)
            hint.frame = NSRect(x: 44, y: 68, width: 410, height: 42)
            let cancel = NSButton(title: "Отмена", target: self, action: #selector(cancelSettings(_:)))
            cancel.bezelStyle = .rounded
            cancel.keyEquivalent = "\u{1b}"
            cancel.frame = NSRect(x: 266, y: 20, width: 90, height: 32)
            let save = NSButton(title: "Сохранить", target: self, action: #selector(saveSettings(_:)))
            save.bezelStyle = .rounded
            save.keyEquivalent = "\r"
            save.frame = NSRect(x: 356, y: 20, width: 100, height: 32)
            for view in [title, checkbox, hint, cancel, save] { sheet.contentView?.addSubview(view) }
            settingsWindow = sheet
            soundCheckbox = checkbox
            settingsHint = hint
        }
        if settingsWindow?.sheetParent == nil {
            reloadAudioPreferences()
            soundCheckbox?.state = ClockPreferences.soundEnabled() ? .on : .off
            settingsHint?.stringValue = "Музыка и сигналы в конце минуты.\nПо умолчанию звук выключен."
            settingsHint?.textColor = .secondaryLabelColor
        }
        return settingsWindow
    }

    @objc private func saveSettings(_ sender: Any?) {
        guard ClockPreferences.setSoundEnabled(soundCheckbox?.state == .on) else {
            settingsHint?.stringValue = "Не удалось сохранить настройку. Попробуйте ещё раз."
            settingsHint?.textColor = .systemRed
            return
        }
        reloadAudioPreferences()
        closeSettings()
    }

    @objc private func cancelSettings(_ sender: Any?) { closeSettings() }

    private func closeSettings() {
        guard let sheet = settingsWindow else { return }
        sheet.sheetParent?.endSheet(sheet)
        sheet.orderOut(nil)
    }

    private func updateAudioFeedback() {
        guard faceView != nil else { return }
        let muted = isAudioMuted
        guard displayedMuteState != muted else { return }
        displayedMuteState = muted
        let status = audio == nil ? "Предпросмотр без звука" : muted ? "Звук выключен. Нажмите, чтобы включить." : "Звук включён. Нажмите, чтобы выключить."
        faceView?.toolTip = status
        audioButton?.title = muted ? "Включить звук" : "Выключить звук"
        audioButton?.toolTip = status
        audioButton?.setAccessibilityLabel(audioButton?.title)
        audioButton?.setAccessibilityValue(muted ? "Звук выключен" : "Звук включён")
    }

    private func showError(_ message: String) {
        let label = NSTextField(wrappingLabelWithString: message)
        label.textColor = .white
        label.font = .systemFont(ofSize: 12)
        label.frame = NSRect(x: 20, y: 20, width: max(bounds.width - 40, 1), height: 44)
        label.autoresizingMask = [.width]
        addSubview(label)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        video?.view.frame = bounds
        CATransaction.commit()
    }

    override func startAnimation() {
        if running { return }
        super.startAnimation()
        running = true
        video?.start()
        reloadAudioPreferences()
        do { try audio?.start(); audioError = nil } catch { audioError = error; NSLog("Cool Clock audio failed: %@", String(describing: error)) }
        animateOneFrame()
    }

    override func stopAnimation() {
        running = false
        video?.stop()
        audio?.stop()
        super.stopAnimation()
    }

    override func animateOneFrame() {
        guard running else { return }
        do { try audio?.recoverIfNeeded() } catch { audioError = error }
        updateAudioFeedback()
        faceView?.audioPhase = audio?.phase
        let renderedTime = video?.lastRenderedSceneTime ?? .nan
        faceView?.animationTime = renderedTime.isFinite ? renderedTime : playbackTime.isFinite ? playbackTime : 0
        faceView?.needsDisplay = true
        submittedFrames += 1
    }
}
