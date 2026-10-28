import AppKit


@main
final class InstallerApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let content = NSStackView()
    private let backButton = NSButton(title: clockText("Cancel", "Отмена"), target: nil, action: nil)
    private let nextButton = NSButton(title: clockText("Continue", "Продолжить"), target: nil, action: nil)
    private let soundButton = NSButton(checkboxWithTitle: clockText("Play music and minute beeps", "Воспроизводить музыку и минутные сигналы"), target: nil, action: nil)
    private var page = 0
    private var installing = false
    private var installedPreview: URL?
    private var openingPreview = false
    private let setupSteps = ClockSetupGuide.steps(for: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    private var coach: SetupCoach?

    static func main() {
        let app = NSApplication.shared
        let delegate = InstallerApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let item = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: clockText("Quit Installer", "Завершить установку"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        menu.addItem(item)
        NSApp.mainMenu = menu

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 420),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = clockText("Install Cool Clock", "Установка Cool Clock")
        window.delegate = self
        window.isReleasedWhenClosed = false
        let root = window.contentView!
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)
        backButton.target = self; backButton.action = #selector(back)
        nextButton.target = self; nextButton.action = #selector(next)
        nextButton.keyEquivalent = "\r"
        for button in [backButton, nextButton] {
            button.bezelStyle = .rounded
            button.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(button)
        }
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            content.bottomAnchor.constraint(lessThanOrEqualTo: backButton.topAnchor, constant: -24),
            backButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            backButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22),
            nextButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            nextButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            nextButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 132)
        ])
        let installedSaver = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Screen Savers/Cool Clock.saver")
        _ = ClockPreferences.applyInstallationChoice(from: installedSaver)
        soundButton.state = ClockPreferences.soundEnabled() ? .on : .off
        showPage()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func label(_ text: String, size: CGFloat = 14, bold: Bool = false) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        label.textColor = bold ? .labelColor : .secondaryLabelColor
        content.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
    }

    private func showPage() {
        for view in content.arrangedSubviews { content.removeArrangedSubview(view); view.removeFromSuperview() }
        content.spacing = page >= 3 ? 12 : 16
        let size = page >= 3 ? NSSize(width: 760, height: 700) : NSSize(width: 610, height: 420)
        if window.contentView?.frame.size != size { window.setContentSize(size); window.center() }
        backButton.isHidden = false
        backButton.isEnabled = !installing
        nextButton.isEnabled = !installing
        window.standardWindowButton(.closeButton)?.isEnabled = !installing
        switch page {
        case 0:
            let icon = NSImageView(image: NSApp.applicationIconImage)
            icon.imageScaling = .scaleProportionallyUpOrDown
            content.addArrangedSubview(icon)
            icon.widthAnchor.constraint(equalToConstant: 72).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 72).isActive = true
            label(clockText("Install Cool Clock", "Установить Cool Clock"), size: 26, bold: true)
            label(clockText("Moving clouds and a clock on your Mac.", "Живые облака и часы на экране вашего Mac."))
            label(clockText("Install the screensaver and preview app for your account. No administrator password is needed.", "Мастер установит заставку и приложение предпросмотра для вашей учётной записи. Пароль администратора не понадобится."))
            let saver = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Screen Savers/Cool Clock.saver")
            if Bundle(url: saver)?.bundleIdentifier == "ru.coolclock.screensaver" {
                let guide = NSButton(title: clockText("Cool Clock is already installed: set up macOS…", "Cool Clock уже установлен: настроить macOS…"), target: self, action: #selector(startSetupGuide))
                guide.bezelStyle = .rounded
                content.addArrangedSubview(guide)
            }
            backButton.title = clockText("Cancel", "Отмена"); nextButton.title = clockText("Continue", "Продолжить")
        case 1:
            label(clockText("Screensaver sound", "Звук заставки"), size: 26, bold: true)
            label(clockText("Choose whether the clock plays sound.", "Выберите, как будут работать часы."))
            content.addArrangedSubview(soundButton)
            label(clockText("With sound off, the clouds and clock keep moving. Music and beeps are muted.", "Когда звук выключен, облака и часы продолжают двигаться. Сигналы и музыка не воспроизводятся."))
            label(clockText("You can change the sound later in the screensaver settings. The preview app has its own sound setting.", "Позже звук заставки можно изменить в её параметрах macOS. У предпросмотра есть собственная настройка звука."))
            backButton.title = clockText("Back", "Назад"); nextButton.title = clockText("Install", "Установить")
        case 2:
            label(clockText("Installing Cool Clock", "Устанавливаем Cool Clock"), size: 26, bold: true)
            label(clockText("Copying the app and screensaver. This will take a moment.", "Копируем приложение и заставку. Это займёт немного времени."))
            let progress = NSProgressIndicator()
            progress.style = .bar
            progress.isIndeterminate = true
            content.addArrangedSubview(progress)
            progress.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
            progress.startAnimation(nil)
            backButton.isHidden = true; nextButton.title = clockText("Installing…", "Установка…")
        default:
            let index = page - 3
            let step = setupSteps[index]
            label(clockText("Cool Clock installed · macOS setup · Step \(index + 1) of \(setupSteps.count)", "Cool Clock установлен · Настройка macOS · Шаг \(index + 1) из \(setupSteps.count)"), size: 12, bold: true)
            label(step.title, size: 25, bold: true)
            label(step.instructions)
            let illustration = SetupGuideView(step: step)
            content.addArrangedSubview(illustration)
            illustration.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
            label(step.footnote, size: 12)
            let actions = NSStackView()
            actions.orientation = .horizontal
            actions.spacing = 12
            let settings = NSButton(title: step.settingsButtonTitle, target: self, action: #selector(openGuideSettings))
            settings.bezelStyle = .rounded
            actions.addArrangedSubview(settings)
            if installedPreview != nil {
                let preview = NSButton(title: clockText("Open clock in a window", "Отдельное окно часов"), target: self, action: #selector(openPreview))
                preview.bezelStyle = .rounded
                actions.addArrangedSubview(preview)
            }
            content.addArrangedSubview(actions)
            label(clockText("Complete this step in System Settings, then return here. Next does not change settings automatically.", "Выполните шаг в системных настройках и вернитесь сюда. Кнопка «Дальше» не меняет настройки автоматически."), size: 12)
            backButton.title = index == 0 ? clockText("Close", "Закрыть") : clockText("Back", "Назад")
            nextButton.title = index == setupSteps.count - 1 ? clockText("Done", "Готово") : clockText("Next", "Дальше")
        }
        if page >= 3, let coach {
            coach.show(step: setupSteps[page - 3], index: page - 3, total: setupSteps.count)
        }
    }

    @objc private func back() {
        guard !installing else { return }
        if page == 1 { page = 0; showPage() }
        else if page > 3 {
            page -= 1; showPage()
            if coach != nil { openSystemSettings(pane: setupSteps[page - 3].pane) }
        }
        else { NSApp.terminate(nil) }
    }

    @objc private func next() {
        if page == 0 { page = 1; showPage() }
        else if page == 1 { install() }
        else if page >= 3 {
            if page - 3 == setupSteps.count - 1 { NSApp.terminate(nil) }
            else {
                page += 1; showPage()
                if coach != nil { openSystemSettings(pane: setupSteps[page - 3].pane) }
            }
        }
    }

    @objc private func startSetupGuide() {
        let preview = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Cool Clock Preview.app")
        if Bundle(url: preview)?.bundleIdentifier == "ru.coolclock.preview" { installedPreview = preview }
        page = 3
        showPage()
    }

    @objc private func openGuideSettings() {
        guard page >= 3, setupSteps.indices.contains(page - 3) else { return }
        let requestedPage = page
        openSystemSettings(pane: setupSteps[page - 3].pane) { [weak self] in
            guard let self, self.page == requestedPage else { return }
            if self.coach == nil {
                self.coach = SetupCoach(onNext: { [weak self] in self?.next() },
                    onBack: { [weak self] in self?.back() },
                    onOpenSettings: { [weak self] in
                        guard let self else { return }
                        self.openSystemSettings(pane: self.setupSteps[self.page - 3].pane)
                    }, onReturn: { [weak self] in self?.returnToInstaller() })
            }
            self.coach?.show(step: self.setupSteps[self.page - 3], index: self.page - 3, total: self.setupSteps.count)
            self.window.orderOut(nil)
        }
    }

    private func returnToInstaller() {
        coach?.stop()
        coach = nil
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func install() {
        guard let payload = Bundle.main.url(forResource: "Cool Clock Preview", withExtension: "app") else {
            showError(clockText("The Cool Clock app is missing from the installer. Download the complete package again.", "В установщике не найдено приложение Cool Clock. Скачайте полный пакет ещё раз."))
            return
        }
        let enabled = soundButton.state == .on
        installing = true; page = 2; showPage()
        let previewURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Cool Clock Preview.app").standardizedFileURL
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "ru.coolclock.preview")
            .filter { $0.bundleURL?.standardizedFileURL == previewURL }
        running.forEach { _ = $0.terminate() }
        waitForPreviewExit(running, deadline: Date().addingTimeInterval(5)) {
            self.copyPayload(payload, soundEnabled: enabled)
        }
    }

    private func waitForPreviewExit(_ apps: [NSRunningApplication], deadline: Date, completion: @escaping () -> Void) {
        if apps.allSatisfy({ $0.isTerminated }) { completion(); return }
        guard Date() < deadline else {
            installing = false; page = 1; showPage()
            showError(clockText("Close Cool Clock Preview and try installing again.", "Закройте Cool Clock Preview и повторите установку."))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.waitForPreviewExit(apps, deadline: deadline, completion: completion)
        }
    }

    private func copyPayload(_ payload: URL, soundEnabled: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try ClockInstallation(payload: payload).install(soundEnabled: soundEnabled) }
            DispatchQueue.main.async {
                self.installing = false
                switch result {
                case .success(let installed): self.installedPreview = installed.preview; self.page = 3; self.showPage()
                case .failure(let error): self.page = 1; self.showPage(); self.showError(error.localizedDescription)
                }
            }
        }
    }

    private func showError(_ message: String) {
        if !window.isVisible { returnToInstaller() }
        let alert = NSAlert()
        alert.messageText = clockText("Could not complete the action", "Не удалось завершить действие")
        alert.informativeText = message
        alert.addButton(withTitle: clockText("OK", "Понятно"))
        alert.beginSheetModal(for: window)
    }

    @objc private func openPreview() {
        guard let url = installedPreview, !openingPreview else { return }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: "ru.coolclock.preview")
            .first(where: { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL }) {
            running.activate(options: .activateIgnoringOtherApps)
            return
        }
        openingPreview = true
        openApplication(url, newInstance: true)
    }

    private func openSystemSettings(pane: String? = nil, onOpen: (() -> Void)? = nil) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else {
            showError(clockText("Open System Settings from the Apple menu and select Cool Clock in Screen Saver settings.", "Откройте системные настройки из меню Apple и выберите Cool Clock в разделе заставок."))
            return
        }
        guard let pane, let url = URL(string: "x-apple.systempreferences:\(pane)") else {
            openApplication(app, onOpen: onOpen)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if error != nil {
                    self.openApplication(app) {
                        self.showError(clockText("The settings link did not open. Follow the path shown in the guide to open the section manually.", "Ссылка на раздел не сработала. Выберите путь из подсказки в системных настройках вручную."))
                    }
                } else { onOpen?() }
            }
        }
    }

    private func openApplication(_ url: URL, newInstance: Bool = false, onOpen: (() -> Void)? = nil) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = newInstance
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if newInstance { self.openingPreview = false }
                if let error { self.showError(error.localizedDescription) }
                else { onOpen?() }
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { !installing }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return installing ? .terminateCancel : .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { coach == nil }
    func applicationWillTerminate(_ notification: Notification) {
        coach?.stop()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let coach, page >= 3 {
            coach.show(step: setupSteps[page - 3], index: page - 3, total: setupSteps.count)
        } else if !flag && !installing { returnToInstaller() }
        return true
    }
}
