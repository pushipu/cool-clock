import Foundation

enum ClockLanguage {
    case english, russian

    static let current = resolve(Locale.preferredLanguages)

    static func resolve(_ preferredLanguages: [String]) -> ClockLanguage {
        let primary = preferredLanguages.first?.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "-" || $0 == "_" }).first?.lowercased()
        return primary == "ru" ? .russian : .english
    }

    func text(_ english: String, _ russian: String) -> String {
        self == .russian ? russian : english
    }
}

func clockText(_ english: String, _ russian: String) -> String {
    ClockLanguage.current.text(english, russian)
}
