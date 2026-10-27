import Foundation

@main
struct SceneSnapshots {
    static func main() throws {
        let scene = try CloudScene(data: Data(contentsOf: URL(fileURLWithPath: "assets/rectangle-tracks.json")))
        let times = [0.0, 3.5, 4, 5.4, 6.08, 7, 12.5, 32, 75, 115.9, -1, 116]
        let snapshots = times.map { ["seconds": $0, "frame": scene.snapshot(at: $0)] as [String: Any] }
        let data = try JSONSerialization.data(withJSONObject: snapshots, options: [.sortedKeys])
        try data.write(to: URL(fileURLWithPath: "tests/fixtures/windows-cloud-scene.json"))
    }
}
