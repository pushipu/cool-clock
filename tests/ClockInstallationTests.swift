import Foundation
import Darwin

private final class FailingFiles: FileManager, @unchecked Sendable {
    var rejectMove: ((URL, URL) -> Bool)?
    var rejectCopy: ((URL, URL) -> Bool)?
    override func moveItem(at source: URL, to destination: URL) throws {
        if rejectMove?(source, destination) == true { throw NSError(domain: "InjectedMoveFailure", code: 1) }
        try super.moveItem(at: source, to: destination)
    }
    override func copyItem(at source: URL, to destination: URL) throws {
        if rejectCopy?(source, destination) == true { throw NSError(domain: "InjectedCopyFailure", code: 1) }
        try super.copyItem(at: source, to: destination)
    }
}

@main struct ClockInstallationTests {
    static let files = FileManager.default
    static var count = 0

    static func check(_ value: Bool, _ message: String) throws {
        if !value { throw NSError(domain: "InstallationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func bundle(_ path: URL, identifier: String, version: String, executable: String, kind: String) throws {
        let contents = path.appendingPathComponent("Contents")
        try files.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": identifier, "CFBundleShortVersionString": version,
                    "CFBundleVersion": "14", "CFBundleExecutable": executable, "CFBundlePackageType": kind]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let binary = contents.appendingPathComponent("MacOS/\(executable)")
        try Data("fixture".utf8).write(to: binary)
        try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    }

    static func payload(_ path: URL, version: String = "0.8.0", saverVersion: String? = nil) throws {
        try bundle(path, identifier: "ru.coolclock.preview", version: version, executable: "CoolClockPreview", kind: "APPL")
        let saver = path.appendingPathComponent("Contents/PlugIns/Cool Clock.saver")
        try bundle(saver, identifier: "ru.coolclock.screensaver", version: saverVersion ?? version, executable: "CoolClock", kind: "BNDL")
        let resources = saver.appendingPathComponent("Contents/Resources")
        try files.createDirectory(at: resources, withIntermediateDirectories: true)
        for name in ["CloudSwift.mp4", "CloudCirrus.mp4", "ClockMinute.wav", "Clouds.metal", "Glyphs.json", "RectangleTracks.json", "Credits.txt", "ClockIcon.icns"] {
            try Data(version.utf8).write(to: resources.appendingPathComponent(name))
        }
    }

    static func test(_ name: String, _ body: (URL, URL, URL) throws -> Void) throws {
        let root = files.temporaryDirectory.appendingPathComponent("cool-clock-install-test-\(UUID().uuidString)")
        try files.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        try files.createDirectory(at: home, withIntermediateDirectories: false)
        let source = root.appendingPathComponent("payload.app")
        try payload(source)
        try body(root, home, source)
        count += 1
        print("PASS: \(name)")
        fflush(stdout)
    }

    static func expectFailure(_ body: () throws -> Void) throws {
        var failed = false
        do { try body() } catch { failed = true }
        try check(failed, "Expected installation failure")
    }

    static func installedVersion(_ path: URL) throws -> String {
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: path.appendingPathComponent("Contents/Info.plist")), format: nil) as! [String: Any]
        return info["CFBundleShortVersionString"] as! String
    }

    static func noStages(_ home: URL) -> Bool {
        !(files.enumerator(at: home, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .contains { $0.lastPathComponent.hasPrefix(".cool-clock-install-") }
    }

    static func choice(_ bundle: URL) throws -> [String: Any] {
        let name = "ru.coolclock.install-settings"
        let size = getxattr(bundle.path, name, nil, 0, 0, 0)
        try check(size > 0 && size < 4096, "Installed choice attribute exists")
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(bundle.path, name, $0.baseAddress, $0.count, 0, 0) }
        try check(read == size, "Installed choice attribute readable")
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    static func main() throws {
        try test("fresh installation and repeated update") { _, home, source in
            let first = try ClockInstallation(payload: source, home: home).install()
            try check(first.saver.path == home.appendingPathComponent("Library/Screen Savers/Cool Clock.saver").resolvingSymlinksInPath().path, "Saver destination")
            try check(first.preview.path == home.appendingPathComponent("Applications/Cool Clock Preview.app").resolvingSymlinksInPath().path, "Preview destination")
            try check(try installedVersion(first.saver) == "0.8.0", "Installed saver version")
            _ = try ClockInstallation(payload: source, home: home).install()
            try check(noStages(home), "Successful install removes staging")
        }
        try test("upgrade replaces both matching bundles") { root, home, source in
            let old = root.appendingPathComponent("old.app")
            try payload(old, version: "0.7.1")
            let targets = try ClockInstallation(payload: old, home: home).install()
            _ = try ClockInstallation(payload: source, home: home).install()
            try check(try installedVersion(targets.saver) == "0.8.0", "Saver upgraded")
            try check(try installedVersion(targets.preview) == "0.8.0", "Preview upgraded")
        }
        try test("sound choice is seeded equally and renewed on reinstall") { _, home, source in
            let targets = try ClockInstallation(payload: source, home: home).install(soundEnabled: true)
            let first = try choice(targets.saver)
            let embedded = try choice(targets.preview.appendingPathComponent("Contents/PlugIns/Cool Clock.saver"))
            try check(first["soundEnabled"] as? Bool == true, "Enabled sound written")
            try check(first["id"] as? String == embedded["id"] as? String && embedded["soundEnabled"] as? Bool == true, "Both hosts receive same choice")
            _ = try ClockInstallation(payload: source, home: home).install(soundEnabled: false)
            let second = try choice(targets.saver)
            try check(second["soundEnabled"] as? Bool == false && second["id"] as? String != first["id"] as? String, "New install overrides prior choice once")
        }
        try test("missing media leaves existing versions intact") { root, home, source in
            let old = root.appendingPathComponent("old.app")
            try payload(old, version: "0.7.1")
            let targets = try ClockInstallation(payload: old, home: home).install()
            try files.removeItem(at: source.appendingPathComponent("Contents/PlugIns/Cool Clock.saver/Contents/Resources/ClockMinute.wav"))
            try expectFailure { _ = try ClockInstallation(payload: source, home: home).install() }
            try check(try installedVersion(targets.preview) == "0.7.1", "Prior version preserved")
        }
        try test("mismatched payload versions rejected") { _, home, source in
            try payload(source, saverVersion: "0.7.1")
            try expectFailure { _ = try ClockInstallation(payload: source, home: home).install() }
            try check(!files.fileExists(atPath: home.appendingPathComponent("Applications").path), "No destinations created")
        }
        try test("unrelated existing app is not replaced") { _, home, source in
            let other = home.appendingPathComponent("Applications/Cool Clock Preview.app")
            try bundle(other, identifier: "someone.else", version: "1.0.0", executable: "Other", kind: "APPL")
            try expectFailure { _ = try ClockInstallation(payload: source, home: home).install() }
            try check(try installedVersion(other) == "1.0.0", "Unrelated app preserved")
            try check(noStages(home), "Prepared files removed on conflict")
        }
        try test("symlink destination ancestor cannot escape home") { root, home, source in
            let outside = root.appendingPathComponent("outside")
            try files.createDirectory(at: outside, withIntermediateDirectories: false)
            try files.createSymbolicLink(at: home.appendingPathComponent("Library"), withDestinationURL: outside)
            try expectFailure { _ = try ClockInstallation(payload: source, home: home).install() }
            try check(try files.contentsOfDirectory(atPath: outside.path).isEmpty, "Outside location unchanged")
        }
        try test("symlink home and payload roots rejected") { root, home, source in
            let alias = root.appendingPathComponent("alias")
            try files.createSymbolicLink(at: alias, withDestinationURL: home)
            try expectFailure { _ = try ClockInstallation(payload: source, home: alias).install() }
            let payloadAlias = root.appendingPathComponent("payload-alias")
            try files.createSymbolicLink(at: payloadAlias, withDestinationURL: source)
            try expectFailure { _ = try ClockInstallation(payload: payloadAlias, home: home).install() }
        }
        try test("copy failure preserves both existing versions") { root, home, source in
            let old = root.appendingPathComponent("old.app")
            try payload(old, version: "0.7.1")
            let targets = try ClockInstallation(payload: old, home: home).install()
            let failing = FailingFiles()
            failing.rejectCopy = { from, _ in from == source }
            try expectFailure { _ = try ClockInstallation(payload: source, home: home, fileManager: failing).install() }
            try check(try installedVersion(targets.saver) == "0.7.1", "Saver preserved after copy failure")
            try check(try installedVersion(targets.preview) == "0.7.1", "Preview preserved after copy failure")
            try check(noStages(home), "Failed copy staging removed")
        }
        try test("second replacement failure rolls back both bundles") { root, home, source in
            let old = root.appendingPathComponent("old.app")
            try payload(old, version: "0.7.1")
            let targets = try ClockInstallation(payload: old, home: home).install()
            let failing = FailingFiles()
            failing.rejectMove = { from, to in from.lastPathComponent == "new.bundle" && to.path == targets.preview.path }
            try expectFailure { _ = try ClockInstallation(payload: source, home: home, fileManager: failing).install() }
            try check(try installedVersion(targets.saver) == "0.7.1", "Saver rolled back")
            try check(try installedVersion(targets.preview) == "0.7.1", "Preview rolled back")
            try check(noStages(home), "Successful rollback staging removed")
        }
        try test("failed rollback retains recoverable backups") { root, home, source in
            let old = root.appendingPathComponent("old.app")
            try payload(old, version: "0.7.1")
            let targets = try ClockInstallation(payload: old, home: home).install()
            let failing = FailingFiles()
            failing.rejectMove = { from, to in to.path == targets.preview.path && ["new.bundle", "previous.bundle"].contains(from.lastPathComponent) }
            var message = ""
            do { _ = try ClockInstallation(payload: source, home: home, fileManager: failing).install() }
            catch { message = error.localizedDescription }
            try check(message.contains("Резервные копии сохранены"), "Recovery locations surfaced")
            let backups = (files.enumerator(at: home, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []).filter { $0.lastPathComponent == "previous.bundle" }
            try check(backups.count == 1, "Failed preview rollback backup retained")
            try check(try installedVersion(backups[0]) == "0.7.1", "Original backup remains readable")
            try check(try installedVersion(targets.saver) == "0.7.1", "Other bundle restored despite rollback failure")
        }
        try test("copied bundle preserves custom extended attributes") { _, home, source in
            let resource = "Contents/PlugIns/Cool Clock.saver/Contents/Resources/Glyphs.json"
            let value = Data("preserved".utf8)
            let status = value.withUnsafeBytes { setxattr(source.appendingPathComponent(resource).path, "com.coolclock.install-test", $0.baseAddress, $0.count, 0, 0) }
            try check(status == 0, "Fixture extended attribute set")
            let targets = try ClockInstallation(payload: source, home: home).install()
            var bytes = [UInt8](repeating: 0, count: 32)
            let size = bytes.withUnsafeMutableBytes { getxattr(targets.preview.appendingPathComponent(resource).path, "com.coolclock.install-test", $0.baseAddress, $0.count, 0, 0) }
            try check(size == value.count && Data(bytes.prefix(value.count)) == value, "Custom extended attribute preserved")
        }
        print("PASS: \(count) installation tests; only disposable homes used")
    }
}
