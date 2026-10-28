import Foundation

struct ClockInstallation {
    let payload: URL
    let home: URL
    private let files: FileManager

    init(payload: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser,
         fileManager: FileManager = .default) {
        self.payload = payload
        self.home = home
        self.files = fileManager
    }

    private struct Stage {
        let target: URL
        let directory: URL
        let identifier: String
        var backedUp = false
        var installed = false
        var fresh: URL { directory.appendingPathComponent("new.bundle") }
        var backup: URL { directory.appendingPathComponent("previous.bundle") }
    }

    func install(soundEnabled: Bool = false) throws -> (saver: URL, preview: URL) {
        try validatePayload(payload)
        guard try type(of: home) == .typeDirectory else {
            throw failure(clockText("The home folder is unavailable or is a symbolic link.", "Домашняя папка недоступна или является ссылкой."))
        }
        let base = home.resolvingSymlinksInPath()
        let saver = base.appendingPathComponent("Library/Screen Savers/Cool Clock.saver")
        let preview = base.appendingPathComponent("Applications/Cool Clock Preview.app")
        let sources = [payload.appendingPathComponent("Contents/PlugIns/Cool Clock.saver"), payload]
        let identifiers = ["ru.coolclock.screensaver", "ru.coolclock.preview"]
        var stages: [Stage] = []
        var retainBackups = false
        defer {
            if !retainBackups {
                for stage in stages { try? files.removeItem(at: stage.directory) }
            }
        }
        do {
            for (index, target) in [saver, preview].enumerated() {
                try validateDestination(target, below: base, identifier: identifiers[index])
                let parent = target.deletingLastPathComponent()
                try files.createDirectory(at: parent, withIntermediateDirectories: true)
                try validateDestination(target, below: base, identifier: identifiers[index])
                let directory = parent.appendingPathComponent(".cool-clock-install-\(UUID().uuidString)")
                try files.createDirectory(at: directory, withIntermediateDirectories: false)
                let stage = Stage(target: target, directory: directory, identifier: identifiers[index])
                stages.append(stage)
                try files.copyItem(at: sources[index], to: stage.fresh)
            }
            try validatePayload(stages[1].fresh)
            let standaloneVersion = try validateSaver(stages[0].fresh)
            let previewVersion = try validateBundle(stages[1].fresh, identifier: identifiers[1], executable: "CoolClockPreview", kind: "APPL")
            guard standaloneVersion == previewVersion else { throw failure(clockText("The package changed while copying. Try installing again.", "Пакет изменился во время копирования. Повторите установку.")) }
            let choiceID = UUID().uuidString
            try ClockPreferences.writeInstallationChoice(soundEnabled: soundEnabled, to: stages[0].fresh, id: choiceID)
            try ClockPreferences.writeInstallationChoice(soundEnabled: soundEnabled,
                to: stages[1].fresh.appendingPathComponent("Contents/PlugIns/Cool Clock.saver"), id: choiceID)
            for index in stages.indices {
                let stage = stages[index]
                try validateDestination(stage.target, below: base, identifier: stage.identifier)
                if try type(of: stage.target) != nil {
                    try files.moveItem(at: stage.target, to: stage.backup)
                    stages[index].backedUp = true
                }
                try files.moveItem(at: stage.fresh, to: stage.target)
                stages[index].installed = true
            }
        } catch {
            var problems: [String] = []
            for stage in stages.reversed() where stage.installed || stage.backedUp {
                do {
                    try validateAncestors(stage.target, below: base)
                    if stage.installed { try files.removeItem(at: stage.target) }
                    if stage.backedUp { try files.moveItem(at: stage.backup, to: stage.target) }
                } catch {
                    problems.append("\(stage.target.path): \(error.localizedDescription)")
                }
            }
            if !problems.isEmpty {
                retainBackups = true
                let backups = stages.map { $0.directory.path }.joined(separator: "\n")
                throw failure(clockText("Installation interrupted: \(error.localizedDescription)\nCould not fully restore the previous version:\n\(problems.joined(separator: "\n"))\nBackups retained:\n\(backups)", "Установка прервана: \(error.localizedDescription)\nНе удалось полностью восстановить предыдущую версию:\n\(problems.joined(separator: "\n"))\nРезервные копии сохранены:\n\(backups)"))
            }
            throw error
        }
        return (saver, preview)
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "CoolClockInstallation", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func type(of url: URL) throws -> FileAttributeType? {
        do { return try files.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
    }

    private func validateAncestors(_ target: URL, below base: URL) throws {
        let prefix = base.path + "/"
        guard target.path.hasPrefix(prefix), try type(of: base) == .typeDirectory else {
            throw failure(clockText("The installation path is outside the home folder, or the home folder is unavailable.", "Путь установки выходит за пределы домашней папки или домашняя папка недоступна."))
        }
        var current = base
        for part in target.path.dropFirst(prefix.count).split(separator: "/") {
            current.appendPathComponent(String(part))
            if let kind = try type(of: current), kind != .typeDirectory {
                throw failure(clockText("Cannot install to \(current.path): expected a folder, not a file or symbolic link.", "Нельзя установить в \(current.path): ожидалась папка, а не файл или ссылка."))
            }
        }
    }

    private func validateDestination(_ target: URL, below base: URL, identifier: String) throws {
        try validateAncestors(target, below: base)
        guard try type(of: target) != nil else { return }
        guard try info(target)["CFBundleIdentifier"] as? String == identifier else {
            throw failure(clockText("Another app exists at \(target.path). It will not be replaced.", "В \(target.path) находится другое приложение. Оно не будет заменено."))
        }
    }

    private func info(_ bundle: URL) throws -> [String: Any] {
        let url = bundle.appendingPathComponent("Contents/Info.plist")
        guard try type(of: url) == .typeRegular,
              let value = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any] else {
            throw failure(clockText("Damaged package: \(bundle.lastPathComponent).", "Повреждён пакет: \(bundle.lastPathComponent)."))
        }
        return value
    }

    private func validateBundle(_ bundle: URL, identifier: String, executable: String, kind: String) throws -> [String] {
        guard try type(of: bundle) == .typeDirectory else { throw failure(clockText("Package not found: \(bundle.lastPathComponent).", "Не найден пакет \(bundle.lastPathComponent).")) }
        let properties = try info(bundle)
        guard properties["CFBundleIdentifier"] as? String == identifier,
              properties["CFBundleExecutable"] as? String == executable,
              properties["CFBundlePackageType"] as? String == kind,
              let version = properties["CFBundleShortVersionString"] as? String,
              version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil,
              let build = properties["CFBundleVersion"] as? String, !build.isEmpty else {
            throw failure(clockText("Invalid package information: \(bundle.lastPathComponent).", "Неверные сведения о пакете \(bundle.lastPathComponent)."))
        }
        let binary = bundle.appendingPathComponent("Contents/MacOS/\(executable)")
        guard try type(of: binary) == .typeRegular, files.isExecutableFile(atPath: binary.path) else {
            throw failure(clockText("Executable not found: \(executable).", "Не найден исполняемый файл \(executable)."))
        }
        return [version, build]
    }

    private func validatePayload(_ preview: URL) throws {
        let previewVersion = try validateBundle(preview, identifier: "ru.coolclock.preview", executable: "CoolClockPreview", kind: "APPL")
        let saver = preview.appendingPathComponent("Contents/PlugIns/Cool Clock.saver")
        let saverVersion = try validateSaver(saver)
        guard previewVersion == saverVersion else { throw failure(clockText("The app and screensaver versions do not match.", "Версии приложения и заставки не совпадают.")) }
        var enumerationError: Error?
        guard let entries = files.enumerator(at: preview, includingPropertiesForKeys: nil, errorHandler: { _, error in
            enumerationError = error
            return false
        }) else { throw failure(clockText("Could not read the installation package.", "Не удалось прочитать установочный пакет.")) }
        for case let url as URL in entries {
            let kind = try type(of: url)
            guard kind == .typeDirectory || kind == .typeRegular else {
                throw failure(clockText("The installation package contains an unsupported link or special file.", "Установочный пакет содержит недопустимую ссылку или специальный файл."))
            }
        }
        if let error = enumerationError { throw error }
    }

    private func validateSaver(_ saver: URL) throws -> [String] {
        let version = try validateBundle(saver, identifier: "ru.coolclock.screensaver", executable: "CoolClock", kind: "BNDL")
        for name in ["CloudSwift.mp4", "CloudCirrus.mp4", "ClockMinute.wav", "Clouds.metal", "Glyphs.json", "RectangleTracks.json", "Credits.txt", "ClockIcon.icns"] {
            let url = saver.appendingPathComponent("Contents/Resources/\(name)")
            guard try type(of: url) == .typeRegular,
                  let size = try files.attributesOfItem(atPath: url.path)[.size] as? NSNumber, size.intValue > 0 else {
                throw failure(clockText("The installer is missing \(name). Download the package again.", "В установщике отсутствует \(name). Скачайте пакет заново."))
            }
        }
        return version
    }
}
