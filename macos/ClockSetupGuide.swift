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
    static func steps(for majorVersion: Int, language: ClockLanguage = .current) -> [ClockSetupStep] {
        let text = language.text
        let modernWallpaper = majorVersion >= 26
        let legacy = majorVersion <= 12
        let saverPath = modernWallpaper ? text("Wallpaper → Screen Saver…", "Обои → Заставка…") : legacy ? text("Desktop & Screen Saver → Screen Saver", "Рабочий стол и заставка → Заставка") : text("Screen Saver", "Заставка")
        let saverPane = modernWallpaper ? "com.apple.Wallpaper-Settings.extension" : legacy ? "com.apple.preference.desktopscreeneffect" : "com.apple.ScreenSaver-Settings.extension"
        let clockPath = modernWallpaper ? text("Wallpaper → Clock Appearance…", "Обои → Внешний вид часов…") : majorVersion >= 14 ? text("Lock Screen", "Экран блокировки") : saverPath
        let clockPane = modernWallpaper ? saverPane : majorVersion >= 14 ? "com.apple.Lock-Screen-Settings.extension" : saverPane
        let clockLabel = modernWallpaper ? text("Show large clock", "Крупные часы") : majorVersion >= 14 ? text("Show large clock", "Показывать крупные часы") : text("Show with clock", "Показать с часами / Show with clock")
        let timerLabel = modernWallpaper ? text("Start Screen Saver…", "Запустить заставку…") : legacy ? text("Start after", "Начинать через / Start after") : text("Start Screen Saver when inactive", "Включать заставку при отсутствии активности")
        let timerPath = modernWallpaper || legacy ? saverPath : majorVersion == 13 ? text("Lock Screen", "Заблокировать экран") : text("Lock Screen", "Экран блокировки")
        let timerPane = modernWallpaper || legacy ? saverPane : "com.apple.Lock-Screen-Settings.extension"
        return [
            ClockSetupStep(id: "saver", title: text("Select Cool Clock", "Выберите Cool Clock"),
                instructions: modernWallpaper
                    ? text("Open Wallpaper, then Screen Saver…. Select Custom. Under Other, click Show All and choose Cool Clock. Then click Done.", "Откройте «Обои», затем «Заставка…». Выберите «Настроить». В категории «Другое» нажмите «Показать все» и выберите Cool Clock. Затем нажмите «Готово».")
                    : text("Open Screen Saver settings and select Cool Clock. If you cannot see it, scroll down or expand Other.", "Откройте раздел заставок и выберите Cool Clock в списке. Если плитка не видна, прокрутите список или раскройте категорию «Другое»."),
                path: saverPath,
                rows: modernWallpaper
                    ? [ClockSetupRow(label: text("Use Screen Saver", "Использовать заставку"), value: text("Custom", "Настроить"), highlighted: true),
                       ClockSetupRow(label: text("Other → Show All", "Другое → Показать все"), value: "Cool Clock", highlighted: true)]
                    : [ClockSetupRow(label: text("Screen Saver", "Заставка"), value: "Cool Clock", highlighted: true)],
                footnote: text("This is the system screensaver. Cool Clock Preview opens the clock in a separate window.", "Это системная заставка. Приложение Cool Clock Preview открывает отдельное окно часов."),
                pane: saverPane, settingsButtonTitle: modernWallpaper ? text("Open Wallpaper", "Открыть «Обои»") : text("Open Screen Saver settings", "Открыть заставки")),
            ClockSetupStep(id: "clock", title: text("Turn off the macOS clock overlay", "Уберите системные часы поверх Cool Clock"),
                instructions: majorVersion >= 14
                    ? text("In \(clockPath), set the large clock to Never. Otherwise, macOS may show its clock over the Cool Clock dial.", "В разделе «\(clockPath)» выберите «Никогда» для крупных часов. Иначе macOS может показывать свои часы поверх циферблата Cool Clock.")
                    : text("In Screen Saver settings, clear Show with clock.", "В параметрах системной заставки снимите флажок «Показать с часами» (Show with clock)."),
                path: clockPath,
                rows: [ClockSetupRow(label: clockLabel, value: majorVersion >= 14 ? text("Never", "Никогда") : text("Off", "Выключено"), highlighted: true)],
                footnote: majorVersion >= 14
                    ? text("On Lock Screen keeps the system clock visible after locking. Select Never to remove that overlay too.", "«На заблокированном экране» оставляет системные часы после блокировки. Чтобы убрать наложение и там, нужен пункт «Никогда».")
                    : text("The checkbox label depends on your macOS version and language.", "Название флажка зависит от языка и версии macOS."),
                pane: clockPane, settingsButtonTitle: modernWallpaper ? text("Open Wallpaper", "Открыть «Обои»") : majorVersion >= 14 ? text("Open Lock Screen settings", "Открыть «Экран блокировки»") : text("Open Screen Saver settings", "Открыть заставки")),
            ClockSetupStep(id: "start", title: text("Set the screensaver start time", "Настройте запуск заставки"),
                instructions: text("Choose how long your Mac should be idle before the clock appears. For example, 2 minutes. Use the interval you prefer.", "Выберите время бездействия, после которого должны появляться часы. Например, 2 минуты. Выберите удобный вам интервал.") + (modernWallpaper ? text(" Click Done in the Screen Saver window after choosing the interval.", " В окне «Заставка» после выбора нажмите «Готово».") : ""),
                path: timerPath,
                rows: [ClockSetupRow(label: timerLabel, value: text("2 minutes — example", "2 минуты — пример"), highlighted: true)],
                footnote: text("Next, check that the display does not turn off before the screensaver starts.", "Следующий шаг поможет проверить, что дисплей не выключается раньше заставки."),
                pane: timerPane, settingsButtonTitle: text("Open screensaver timer", "Открыть таймер заставки")),
            ClockSetupStep(id: "display", title: text("Keep the display on long enough", "Дайте заставке время на экране"),
                instructions: text("The display should turn off after the screensaver starts. For example: screensaver after 2 minutes, display after 10. On a laptop, check both battery and power adapter settings.", "Таймер выключения дисплея должен быть больше таймера заставки. Например: заставка через 2 минуты, дисплей через 10 минут. На ноутбуке проверьте питание от аккумулятора и от сети."),
                path: legacy ? text("Battery / Energy Saver", "Аккумулятор / Экономия энергии") : majorVersion == 13 ? text("Lock Screen", "Заблокировать экран") : text("Lock Screen", "Экран блокировки"),
                rows: [ClockSetupRow(label: text("Turn display off when inactive", "Выключать дисплей в неактивном режиме"), value: text("10 minutes — example", "10 минут — пример"), highlighted: true),
                       ClockSetupRow(label: text("Require password", "Запрашивать пароль"), value: text("Your setting", "Ваше значение"), highlighted: false)],
                footnote: text("Keep your preferred password requirement. You do not need to change it to remove the clock overlay.", "Настройку запроса пароля оставьте как у вас принято. Для исправления наложения часов её менять не нужно."),
                pane: legacy ? nil : "com.apple.Lock-Screen-Settings.extension", settingsButtonTitle: text("Open display settings", "Открыть настройки дисплея")),
            ClockSetupStep(id: "check", title: text("Check the screensaver after locking", "Проверьте заставку после блокировки"),
                instructions: text("First, click Preview in Screen Saver settings. Then lock your Mac (⌃⌘Q), wait for the screensaver, and check that the large macOS clock does not cover Cool Clock. Unlock your Mac and return to the wizard.", "Сначала запустите «Просмотр» в системном разделе заставок. Затем заблокируйте Mac (⌃⌘Q), дождитесь заставки и убедитесь, что поверх Cool Clock нет крупных системных часов. После разблокировки вернитесь к мастеру."),
                path: text("Check on your Mac", "Проверка на вашем Mac"),
                rows: [ClockSetupRow(label: text("Clouds and dial", "Облака и циферблат"), value: "Cool Clock", highlighted: true),
                       ClockSetupRow(label: text("Large macOS clock", "Крупные системные часы"), value: text("Not shown", "Не отображаются"), highlighted: true)],
                footnote: text("Your avatar and login controls belong to macOS and may remain visible. The wizard does not check your changes automatically.", "Аватар и элементы входа принадлежат macOS и могут оставаться на экране. Мастер не проверяет изменения автоматически."),
                pane: saverPane, settingsButtonTitle: text("Open Screen Saver settings", "Открыть заставки"))
        ]
    }
}
