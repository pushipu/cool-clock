import AppKit

/// A user-driven companion to System Settings; it never inspects or changes controls.
final class SetupCoach: NSObject, NSWindowDelegate {
    private let onNext: () -> Void
    private let onBack: () -> Void
    private let onOpenSettings: () -> Void
    private let onReturn: () -> Void
    private let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 620),
                                styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                                backing: .buffered, defer: false)
    private var timer: Timer?
    private var manuallyPositioned = false
    private var expectedFrame: NSRect?

    init(onNext: @escaping () -> Void, onBack: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void, onReturn: @escaping () -> Void) {
        self.onNext = onNext
        self.onBack = onBack
        self.onOpenSettings = onOpenSettings
        self.onReturn = onReturn
        super.init()
        panel.title = clockText("Set up Cool Clock", "Настройка Cool Clock")
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show(step: ClockSetupStep, index: Int, total: Int) {
        let root = NSView()
        panel.contentView = root
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)
        let stack = SetupCoachDocumentView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack
        func label(_ text: String, size: CGFloat, bold: Bool = false, secondary: Bool = false) {
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
            label.textColor = secondary ? .secondaryLabelColor : .labelColor
            stack.addArrangedSubview(label)
        }
        label(clockText("STEP \(index + 1) OF \(total)", "ШАГ \(index + 1) ИЗ \(total)"), size: 11, bold: true, secondary: true)
        label(step.title, size: 20, bold: true)
        label(step.instructions, size: 14)
        stack.addArrangedSubview(SetupGuideView(step: step, compact: true))
        label(step.footnote, size: 12, secondary: true)
        let nextTitle = index == total - 1 ? clockText("Done", "Готово") : clockText("Next", "Далее")
        label(clockText("Complete the step in settings, then click \(nextTitle). Check the result yourself.", "Выполните шаг в настройках, затем нажмите «\(nextTitle)». Проверка — вручную."), size: 12, secondary: true)
        for child in stack.arrangedSubviews {
            child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            child.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        let back = button(clockText("Back", "Назад"), action: #selector(goBack))
        back.isEnabled = index > 0
        let next = button(nextTitle, action: #selector(goNext))
        next.keyEquivalent = "\r"
        let open = button(clockText("Open settings again", "Открыть настройки ещё раз"), action: #selector(openSettings))
        let exit = button(clockText("Return to installer", "Вернуться к установке"), action: #selector(returnToInstaller))
        exit.keyEquivalent = "\u{1b}"
        let navigation = NSStackView(views: [back, next])
        navigation.distribution = .fillEqually
        navigation.spacing = 12
        let controls = NSStackView(views: [navigation, open, exit])
        controls.orientation = .vertical
        controls.alignment = .centerX
        controls.spacing = 6
        controls.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(controls)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            scroll.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            controls.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            controls.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            controls.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
            navigation.widthAnchor.constraint(equalTo: controls.widthAnchor)
        ])
        root.layoutSubtreeIfNeeded()
        stack.scroll(.zero)
        panel.initialFirstResponder = next
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        }
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        panel.orderOut(nil)
        manuallyPositioned = false
        expectedFrame = nil
    }

    deinit {
        timer?.invalidate()
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    @objc private func goNext() { onNext() }
    @objc private func goBack() { onBack() }
    @objc private func openSettings() { onOpenSettings() }
    @objc private func returnToInstaller() { onReturn() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { onReturn(); return false }
    func windowDidMove(_ notification: Notification) {
        if timer != nil, let expected = expectedFrame, panel.frame.origin != expected.origin {
            manuallyPositioned = true
        }
    }

    @objc private func refresh() {
        guard timer != nil else { return }
        let settings = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first
        let windows = settings.map { Self.settingsWindows(processID: $0.processIdentifier) }
        let settingsFrame = windows?.main
        let popovers = windows?.popovers ?? []
        let settingsScreen = settingsFrame.flatMap { frame in
            NSScreen.screens.max { Self.overlap($0.frame, frame) < Self.overlap($1.frame, frame) }
        }
        guard let screen = (manuallyPositioned ? panel.screen : nil) ?? settingsScreen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.insetBy(dx: 10, dy: 10)
        let size = NSSize(width: min(420, visible.width), height: min(642, visible.height))
        let manualFrame = Self.clamp(NSRect(origin: panel.frame.origin, size: size), to: visible)
        let frame = manuallyPositioned && !popovers.contains(where: { manualFrame.intersects($0.insetBy(dx: -8, dy: -8)) })
            ? manualFrame
            : Self.panelFrame(settingsFrame: settingsFrame, visibleFrame: visible, panelSize: size, avoiding: popovers)
        if frame != panel.frame {
            expectedFrame = frame
            panel.setFrame(frame, display: true)
        }
        if !panel.isVisible { panel.orderFront(nil) }
    }

    private static func overlap(_ screen: NSRect, _ window: NSRect?) -> CGFloat {
        guard let window = window else { return 0 }
        let intersection = screen.intersection(window)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private static func settingsWindows(processID: pid_t) -> (main: NSRect?, popovers: [NSRect]) {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return (nil, []) }
        let frames = windows.compactMap { window -> (frame: NSRect, layer: Int)? in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processID,
                  let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer >= 0 && layer <= CGWindowLevelForKey(.popUpMenuWindow),
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.width > 40, rect.height > 20 else { return nil }
            return (NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height), layer)
        }
        let main = frames.filter { $0.layer == 0 && $0.frame.width > 300 && $0.frame.height > 200 }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?.frame
        return (main, frames.map(\.frame).filter { $0 != main })
    }

    static func panelFrame(settingsFrame: NSRect?, visibleFrame: NSRect, panelSize: NSSize, avoiding popovers: [NSRect] = []) -> NSRect {
        let size = NSSize(width: min(panelSize.width, visibleFrame.width), height: min(panelSize.height, visibleFrame.height))
        var x = visibleFrame.maxX - size.width
        var y = visibleFrame.maxY - size.height
        if let settings = settingsFrame {
            y = settings.maxY - size.height
            if settings.maxX + 12 + size.width <= visibleFrame.maxX { x = settings.maxX + 12 }
            else if settings.minX - 12 - size.width >= visibleFrame.minX { x = settings.minX - 12 - size.width }
        }
        let preferred = clamp(NSRect(origin: NSPoint(x: x, y: y), size: size), to: visibleFrame)
        guard !popovers.isEmpty else { return preferred }
        let obstacles = popovers.map { $0.insetBy(dx: -8, dy: -8) }
        var origins = [preferred.origin,
                       NSPoint(x: visibleFrame.minX, y: preferred.minY),
                       NSPoint(x: visibleFrame.maxX - size.width, y: preferred.minY)]
        for popup in obstacles {
            origins += [NSPoint(x: popup.minX - size.width, y: preferred.minY),
                        NSPoint(x: popup.maxX, y: preferred.minY),
                        NSPoint(x: preferred.minX, y: popup.maxY),
                        NSPoint(x: preferred.minX, y: popup.minY - size.height)]
        }
        let candidates = origins.map { clamp(NSRect(origin: $0, size: size), to: visibleFrame) }
        func score(_ frame: NSRect) -> (CGFloat, CGFloat, CGFloat) {
            let popupOverlap = obstacles.reduce(CGFloat.zero) { $0 + overlap(frame, $1) }
            let movement = abs(frame.minX - preferred.minX) + abs(frame.minY - preferred.minY)
            return (popupOverlap, overlap(frame, settingsFrame), movement)
        }
        return candidates.min { score($0) < score($1) } ?? preferred
    }

    private static func clamp(_ frame: NSRect, to visible: NSRect) -> NSRect {
        NSRect(x: min(max(frame.minX, visible.minX), visible.maxX - frame.width),
               y: min(max(frame.minY, visible.minY), visible.maxY - frame.height),
               width: frame.width, height: frame.height)
    }
}

private final class SetupCoachDocumentView: NSStackView {
    override var isFlipped: Bool { true }
}
