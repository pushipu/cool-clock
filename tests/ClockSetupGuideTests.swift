import Foundation

@main struct ClockSetupGuideTests {
    static func main() {
        for major in [12, 13, 14, 15, 26, 27] {
            let steps = ClockSetupGuide.steps(for: major)
            precondition(steps.map(\.id) == ["saver", "clock", "start", "display", "check"])
            precondition(steps.allSatisfy { !$0.title.isEmpty && !$0.instructions.isEmpty && !$0.rows.isEmpty })
            precondition(steps.allSatisfy { $0.rows.contains { $0.highlighted } })
            let clock = steps[1]
            if major >= 26 {
                precondition(clock.path == "Обои → Внешний вид часов…")
                precondition(clock.rows[0].label == "Крупные часы" && clock.rows[0].value == "Никогда")
                precondition(clock.pane == "com.apple.Wallpaper-Settings.extension")
            } else if major >= 14 {
                precondition(clock.path == "Экран блокировки")
                precondition(clock.rows[0].value == "Никогда")
                precondition(clock.pane == "com.apple.Lock-Screen-Settings.extension")
            } else {
                precondition(clock.rows[0].value == "Выключено")
            }
            if (13...15).contains(major) {
                precondition(steps[2].pane == "com.apple.Lock-Screen-Settings.extension")
            }
            precondition(steps[3].footnote.contains("пароля"))
            precondition(steps[4].instructions.contains("заблокируйте Mac"))
            precondition(steps[4].pane == steps[0].pane)
        }
        print("PASS: setup routes for macOS 12, 13, 14, 15, 26 and 27; full clock removal and lock-screen check")
    }
}
