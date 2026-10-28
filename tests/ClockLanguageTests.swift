import Foundation

@main struct ClockLanguageTests {
    static func main() {
        for tag in ["ru", "ru-RU", "ru-BY", "ru_RU", "RU-ru"] {
            precondition(ClockLanguage.resolve([tag, "en-US"]) == .russian, tag)
        }
        for languages in [[], [""], ["en-US"], ["en-US", "ru-RU"], ["de-DE", "ru"], ["uk-UA"], ["russian"], ["-ru"]] {
            precondition(ClockLanguage.resolve(languages) == .english, "Only a Russian primary UI language selects Russian: \(languages)")
        }
        precondition(ClockLanguage.english.text("Save", "Сохранить") == "Save")
        precondition(ClockLanguage.russian.text("Save", "Сохранить") == "Сохранить")
        if let index = CommandLine.arguments.firstIndex(of: "--expect"), index + 1 < CommandLine.arguments.count {
            precondition(clockText("en", "ru") == CommandLine.arguments[index + 1], "Process UI language matches expected selection")
        }
        print("PASS: primary UI language selection, Russian region variants and English fallback")
    }
}
