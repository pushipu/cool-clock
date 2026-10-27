import AppKit

@main
final class InstallerApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let content = NSStackView()
    private let backButton = NSButton(title: "Отмена", target: nil, action: nil)
    private let nextButton = NSButton(title: "Продолжить", target: nil, action: nil)
    private let soundButton = NSButton(checkboxWithTitle: "Воспроизводить музыку и минутные сигналы", target: nil, action: nil)
    private var page = 0
    private var installing = false
    private var installedPreview: URL?
    private var openingPreview = false

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
        appMenu.addItem(withTitle: "Завершить установку", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        menu.addItem(item)
        NSApp.mainMenu = menu

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 420),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Установка Cool Clock"
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
            label("Установить Cool Clock", size: 26, bold: true)
            label("Живые облака и часы на экране вашего Mac.")
            label("Мастер установит заставку и приложение предпросмотра для вашей учётной записи. Пароль администратора не понадобится.")
            backButton.title = "Отмена"; nextButton.title = "Продолжить"
        case 1:
            label("Звук заставки", size: 26, bold: true)
            label("Выберите, как будут работать часы.")
            content.addArrangedSubview(soundButton)
            label("Когда звук выключен, облака и часы продолжают двигаться. Сигналы и музыка не воспроизводятся.")
            label("Позже звук заставки можно изменить в её параметрах macOS. У предпросмотра есть собственная настройка звука.")
            backButton.title = "Назад"; nextButton.title = "Установить"
        case 2:
            label("Устанавливаем Cool Clock", size: 26, bold: true)
            label("Копируем приложение и заставку. Это займёт немного времени.")
            let progress = NSProgressIndicator()
            progress.style = .bar
            progress.isIndeterminate = true
            content.addArrangedSubview(progress)
            progress.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
            progress.startAnimation(nil)
            backButton.isHidden = true; nextButton.title = "Установка…"
        default:
            label("Cool Clock установлен", size: 26, bold: true)
            label(soundButton.state == .on ? "Звук включён." : "Звук выключен.")
            label("Откройте настройки macOS и выберите Cool Clock в разделе заставок. В новых версиях macOS этот раздел может находиться внутри «Обои».")
            let preview = NSButton(title: "Открыть предпросмотр", target: self, action: #selector(openPreview))
            preview.bezelStyle = .rounded
            content.addArrangedSubview(preview)
            backButton.title = "Готово"; nextButton.title = "Открыть настройки macOS"
        }
    }

    @objc private func back() {
        guard !installing else { return }
        if page == 1 { page = 0; showPage() } else { NSApp.terminate(nil) }
    }

    @objc private func next() {
        if page == 0 { page = 1; showPage() }
        else if page == 1 { install() }
        else if page == 3 { openSystemSettings() }
    }

    private func install() {
        guard let payload = Bundle.main.url(forResource: "Cool Clock Preview", withExtension: "app") else {
            showError("В установщике не найдено приложение Cool Clock. Скачайте полный пакет ещё раз.")
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
            showError("Закройте Cool Clock Preview и повторите установку.")
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
        let alert = NSAlert()
        alert.messageText = "Не удалось завершить действие"
        alert.informativeText = message
        alert.addButton(withTitle: "Понятно")
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

    private func openSystemSettings() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else {
            showError("Откройте системные настройки из меню Apple и выберите Cool Clock в разделе заставок.")
            return
        }
        openApplication(url)
    }

    private func openApplication(_ url: URL, newInstance: Bool = false) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = newInstance
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if newInstance { self.openingPreview = false }
                if let error { self.showError(error.localizedDescription) }
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { !installing }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { installing ? .terminateCancel : .terminateNow }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
