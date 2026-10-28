import Foundation

struct ClockSetupRow {
    let label: String
    let value: String
    let highlighted: Bool
}

struct ClockSetupStep {
    let id: String
    let title: String
    let instructions: String
    let path: String
    let rows: [ClockSetupRow]
    let footnote: String
    let pane: String?
    let settingsButtonTitle: String
}

enum ClockSetupGuide {
    static func steps(for majorVersion: Int) -> [ClockSetupStep] {
        let modernWallpaper = majorVersion >= 26
        let legacy = majorVersion <= 12
        let saverPath = modernWallpaper ? "Обои → Заставка…" : legacy ? "Рабочий стол и заставка → Заставка" : "Заставка"
        let saverPane = modernWallpaper ? "com.apple.Wallpaper-Settings.extension" : legacy ? "com.apple.preference.desktopscreeneffect" : "com.apple.ScreenSaver-Settings.extension"
        let clockPath = modernWallpaper ? "Обои → Внешний вид часов…" : majorVersion >= 14 ? "Экран блокировки" : saverPath
        let clockPane = modernWallpaper ? saverPane : majorVersion >= 14 ? "com.apple.Lock-Screen-Settings.extension" : saverPane
        let clockLabel = modernWallpaper ? "Крупные часы" : majorVersion >= 14 ? "Показывать крупные часы" : "Показать с часами / Show with clock"
        let timerLabel = modernWallpaper ? "Запустить заставку…" : legacy ? "Начинать через / Start after" : "Включать заставку при отсутствии активности"
        let timerPath = modernWallpaper || legacy ? saverPath : majorVersion == 13 ? "Заблокировать экран" : "Экран блокировки"
        let timerPane = modernWallpaper || legacy ? saverPane : "com.apple.Lock-Screen-Settings.extension"
        return [
            ClockSetupStep(id: "saver", title: "Выберите Cool Clock",
                instructions: modernWallpaper
                    ? "Откройте «Обои», затем «Заставка…». Выберите «Настроить». В категории «Другое» нажмите «Показать все» и выберите Cool Clock. Затем нажмите «Готово»."
                    : "Откройте раздел заставок и выберите Cool Clock в списке. Если плитка не видна, прокрутите список или раскройте категорию «Другое».",
                path: saverPath,
                rows: modernWallpaper
                    ? [ClockSetupRow(label: "Использовать заставку", value: "Настроить", highlighted: true),
                       ClockSetupRow(label: "Другое → Показать все", value: "Cool Clock", highlighted: true)]
                    : [ClockSetupRow(label: "Заставка", value: "Cool Clock", highlighted: true)],
                footnote: "Это системная заставка. Приложение Cool Clock Preview открывает отдельное окно часов.",
                pane: saverPane, settingsButtonTitle: modernWallpaper ? "Открыть «Обои»" : "Открыть заставки"),
            ClockSetupStep(id: "clock", title: "Уберите системные часы поверх Cool Clock",
                instructions: majorVersion >= 14
                    ? "В разделе «\(clockPath)» выберите «Никогда» для крупных часов. Иначе macOS может показывать свои часы поверх циферблата Cool Clock."
                    : "В параметрах системной заставки снимите флажок «Показать с часами» (Show with clock).",
                path: clockPath,
                rows: [ClockSetupRow(label: clockLabel, value: majorVersion >= 14 ? "Никогда" : "Выключено", highlighted: true)],
                footnote: majorVersion >= 14
                    ? "«На заблокированном экране» оставляет системные часы после блокировки. Чтобы убрать наложение и там, нужен пункт «Никогда»."
                    : "Название флажка зависит от языка и версии macOS.",
                pane: clockPane, settingsButtonTitle: modernWallpaper ? "Открыть «Обои»" : majorVersion >= 14 ? "Открыть «Экран блокировки»" : "Открыть заставки"),
            ClockSetupStep(id: "start", title: "Настройте запуск заставки",
                instructions: "Выберите время бездействия, после которого должны появляться часы. Например, 2 минуты. Выберите удобный вам интервал." + (modernWallpaper ? " В окне «Заставка» после выбора нажмите «Готово»." : ""),
                path: timerPath,
                rows: [ClockSetupRow(label: timerLabel, value: "2 минуты — пример", highlighted: true)],
                footnote: "Следующий шаг поможет проверить, что дисплей не выключается раньше заставки.",
                pane: timerPane, settingsButtonTitle: "Открыть таймер заставки"),
            ClockSetupStep(id: "display", title: "Дайте заставке время на экране",
                instructions: "Таймер выключения дисплея должен быть больше таймера заставки. Например: заставка через 2 минуты, дисплей через 10 минут. На ноутбуке проверьте питание от аккумулятора и от сети.",
                path: legacy ? "Аккумулятор / Экономия энергии" : majorVersion == 13 ? "Заблокировать экран" : "Экран блокировки",
                rows: [ClockSetupRow(label: "Выключать дисплей в неактивном режиме", value: "10 минут — пример", highlighted: true),
                       ClockSetupRow(label: "Запрашивать пароль", value: "Ваше значение", highlighted: false)],
                footnote: "Настройку запроса пароля оставьте как у вас принято. Для исправления наложения часов её менять не нужно.",
                pane: legacy ? nil : "com.apple.Lock-Screen-Settings.extension", settingsButtonTitle: "Открыть настройки дисплея"),
            ClockSetupStep(id: "check", title: "Проверьте заставку после блокировки",
                instructions: "Сначала запустите «Просмотр» в системном разделе заставок. Затем заблокируйте Mac (⌃⌘Q), дождитесь заставки и убедитесь, что поверх Cool Clock нет крупных системных часов. После разблокировки вернитесь к мастеру.",
                path: "Проверка на вашем Mac",
                rows: [ClockSetupRow(label: "Облака и циферблат", value: "Cool Clock", highlighted: true),
                       ClockSetupRow(label: "Крупные системные часы", value: "Не отображаются", highlighted: true)],
                footnote: "Аватар и элементы входа принадлежат macOS и могут оставаться на экране. Мастер не проверяет изменения автоматически.",
                pane: saverPane, settingsButtonTitle: "Открыть заставки")
        ]
    }
}
