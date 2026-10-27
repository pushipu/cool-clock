import Foundation
import ScreenSaver
import Darwin

@main
struct ClockPreferencesTests {
    static func main() throws {
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "ClockPreferencesTests", code: 1,
                                           userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let arguments = CommandLine.arguments
        if arguments.count == 4 {
            let domain = arguments[2]
            try check(domain.hasPrefix("ru.coolclock.tests."), "Only an isolated test domain may be written")
            let defaults = ScreenSaverDefaults(forModuleWithName: domain)!
            let expected = arguments[3] == "true"
            if arguments[1] == "write" {
                try check(ClockPreferences.setSoundEnabled(expected, defaults: defaults), "Child preference write")
            } else {
                try check(arguments[1] == "read", "Unknown child operation")
                try check(ClockPreferences.soundEnabled(defaults: defaults) == expected, "Independent process reads saved sound")
            }
            return
        }
        let domain = "ru.coolclock.tests.\(UUID().uuidString)"
        let defaults = ScreenSaverDefaults(forModuleWithName: domain)!
        defer {
            defaults.removeObject(forKey: ClockPreferences.soundKey)
            defaults.removeObject(forKey: "InstalledChoiceID")
            defaults.synchronize()
        }
        func child(_ operation: String, _ value: Bool) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: arguments[0])
            process.arguments = [operation, domain, value ? "true" : "false"]
            try process.run()
            process.waitUntilExit()
            try check(process.terminationStatus == 0, "Independent process completed")
        }
        try check(!ClockPreferences.soundEnabled(defaults: defaults), "Fresh settings are silent")
        try check(!ClockPreferences.soundEnabled(defaults: nil), "Unavailable preferences are silent")
        try check(!ClockPreferences.setSoundEnabled(true, defaults: nil), "Unavailable storage reports failure")
        try check(ClockPreferences.setSoundEnabled(true, defaults: defaults), "Sound can be enabled")
        try child("read", true)
        try child("write", false)
        try check(!ClockPreferences.soundEnabled(defaults: defaults), "Existing reader sees another process's change")
        try check(ClockPreferences.setSoundEnabled(true, defaults: defaults), "Sound can be enabled again")
        try check(ClockPreferences.setSoundEnabled(false, defaults: defaults), "Sound can be disabled")
        try child("read", false)
        let bundleURL = FileManager.default.temporaryDirectory.appendingPathComponent("CoolClock-\(UUID().uuidString).saver")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: bundleURL) }
        try check(ClockPreferences.applyInstallationChoice(from: bundleURL, defaults: defaults), "Absent installation seed is harmless")
        try check(!ClockPreferences.soundEnabled(defaults: defaults), "Absent seed preserves sound setting")
        let firstID = UUID().uuidString
        try ClockPreferences.writeInstallationChoice(soundEnabled: true, to: bundleURL, id: firstID)
        try check(!ClockPreferences.applyInstallationChoice(from: bundleURL, defaults: nil), "Seed import reports unavailable preference storage")
        try check(ClockPreferences.applyInstallationChoice(from: bundleURL, defaults: defaults), "Installation choice imports")
        try check(ClockPreferences.soundEnabled(defaults: defaults), "Installation can enable sound")
        try check(ClockPreferences.setSoundEnabled(false, defaults: defaults), "Manual edit after installation saves")
        try check(ClockPreferences.applyInstallationChoice(from: bundleURL, defaults: defaults), "Same installation is accepted")
        try check(!ClockPreferences.soundEnabled(defaults: defaults), "Same installation preserves subsequent manual edits")
        try ClockPreferences.writeInstallationChoice(soundEnabled: true, to: bundleURL, id: UUID().uuidString)
        try check(ClockPreferences.applyInstallationChoice(from: bundleURL, defaults: defaults), "New installation imports its choice")
        try check(ClockPreferences.soundEnabled(defaults: defaults), "New installation can override the previous choice")
        try ClockPreferences.writeInstallationChoice(soundEnabled: false, to: bundleURL, id: UUID().uuidString)
        try check(ClockPreferences.applyInstallationChoice(from: bundleURL, defaults: defaults), "New silent installation imports")
        try check(!ClockPreferences.soundEnabled(defaults: defaults), "New installation can disable sound")
        for bytes in [Data(), Data("{}".utf8), Data("{\"schema\":1,\"id\":\"bad\",\"soundEnabled\":true}".utf8), Data(repeating: 65, count: 4097)] {
            let result = bytes.withUnsafeBytes { buffer in
                setxattr(bundleURL.path, "ru.coolclock.install-settings", buffer.baseAddress, buffer.count, 0, 0)
            }
            try check(result == 0, "Malformed seed fixture writes")
            try check(!ClockPreferences.applyInstallationChoice(from: bundleURL, defaults: defaults), "Malformed seed reports failure")
            try check(!ClockPreferences.soundEnabled(defaults: defaults), "Malformed seed cannot turn sound on")
        }
        try check(!ClockPreferences.applyInstallationChoice(from: bundleURL.appendingPathComponent("missing"), defaults: defaults), "Missing bundle reports read failure")
        try check(!ClockPreferences.soundEnabled(defaults: defaults), "Read failure preserves sound setting")
        do {
            try ClockPreferences.writeInstallationChoice(soundEnabled: true, to: bundleURL, id: "invalid")
            throw NSError(domain: "ClockPreferencesTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid installation identifier was accepted"])
        } catch let error as NSError {
            try check(error.domain == "CoolClockPreferences", "Invalid identifier is rejected by writer")
        }
        print("PASS: silent defaults, persistence, independent-process reload, bounded installation import and manual-edit preservation")
    }
}
