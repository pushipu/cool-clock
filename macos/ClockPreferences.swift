import ScreenSaver
import Darwin

enum ClockPreferences {
    static let moduleName = "ru.coolclock.screensaver"
    static let soundKey = "SoundEnabled"
    private static let installationKey = "InstalledChoiceID"
    private static let installationAttribute = "ru.coolclock.install-settings"

    private struct InstallationChoice: Codable {
        let schema: Int
        let id: String
        let soundEnabled: Bool
    }

    // Each host stores preferences in its own module domain, including sandboxed hosts.
    static func soundEnabled(defaults: UserDefaults? = ScreenSaverDefaults(forModuleWithName: moduleName)) -> Bool {
        guard let defaults else { return false }
        defaults.synchronize()
        return defaults.bool(forKey: soundKey)
    }

    @discardableResult
    static func setSoundEnabled(_ value: Bool, defaults: UserDefaults? = ScreenSaverDefaults(forModuleWithName: moduleName)) -> Bool {
        guard let defaults else { return false }
        let oldValue = defaults.object(forKey: soundKey)
        defaults.set(value, forKey: soundKey)
        if defaults.synchronize() { return true }
        defaults.set(oldValue, forKey: soundKey)
        defaults.synchronize()
        return false
    }

    static func writeInstallationChoice(soundEnabled: Bool, to bundleURL: URL, id: String) throws {
        guard bundleURL.isFileURL, let uuid = UUID(uuidString: id) else {
            throw NSError(domain: "CoolClockPreferences", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid installation preference destination or identifier"])
        }
        let data = try JSONEncoder().encode(InstallationChoice(schema: 1, id: uuid.uuidString, soundEnabled: soundEnabled))
        let result = data.withUnsafeBytes { bytes in
            setxattr(bundleURL.path, installationAttribute, bytes.baseAddress, bytes.count, 0, 0)
        }
        if result != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    @discardableResult
    static func applyInstallationChoice(from bundleURL: URL, defaults: UserDefaults? = ScreenSaverDefaults(forModuleWithName: moduleName)) -> Bool {
        guard bundleURL.isFileURL else { return false }
        let size = getxattr(bundleURL.path, installationAttribute, nil, 0, 0, 0)
        if size < 0 { return errno == ENOATTR }
        guard size > 0, size <= 4096 else { return false }
        var data = Data(count: size)
        let count = data.withUnsafeMutableBytes { bytes in
            getxattr(bundleURL.path, installationAttribute, bytes.baseAddress, bytes.count, 0, 0)
        }
        guard count == size,
              let choice = try? JSONDecoder().decode(InstallationChoice.self, from: data),
              choice.schema == 1, let uuid = UUID(uuidString: choice.id) else { return false }
        guard let defaults else { return false }
        guard defaults.synchronize() else { return false }
        if defaults.string(forKey: installationKey) == uuid.uuidString { return true }
        let oldSound = defaults.object(forKey: soundKey)
        let oldIdentifier = defaults.object(forKey: installationKey)
        defaults.set(choice.soundEnabled, forKey: soundKey)
        defaults.set(uuid.uuidString, forKey: installationKey)
        if defaults.synchronize() { return true }
        defaults.set(oldSound, forKey: soundKey)
        defaults.set(oldIdentifier, forKey: installationKey)
        defaults.synchronize()
        return false
    }
}
