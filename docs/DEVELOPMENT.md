# Сборка и проверки

Инструкции для работы с исходным кодом. Готовые установщики находятся на [главной странице](../README.md).

## macOS

Нужны macOS, Xcode Command Line Tools, Python 3 и Node.js для тестов. Сторонних Swift-пакетов нет.

```sh
git clone https://github.com/pushipu/cool-clock.git
cd cool-clock
python3 scripts/fetch-media.py
./build-macos.sh
```

Сборка создаёт универсальные `Cool Clock.saver`, `Cool Clock Preview.app` и `Cool Clock Installer.app` в `build/`. Поддерживаются Apple Silicon и Intel, начиная с macOS 12.

Видео и аудио загружаются из проверенного архива выпуска 0.7.1. Загрузчик сверяет SHA-256 архива и каждого файла. Для сборки без сети передайте архив вручную:

```sh
python3 scripts/fetch-media.py --archive /path/to/Cool-Clock-0.7.1-saver.zip
```

Проверки модели и установщика:

```sh
npm test
python3 -m unittest discover -s tests -p 'test_*.py'
xcrun swiftc -swift-version 5 -module-cache-path build/ModuleCache -framework ScreenSaver macos/ClockPreferences.swift tests/ClockPreferencesTests.swift -o build/preferences-tests
build/preferences-tests
xcrun swiftc -swift-version 5 -module-cache-path build/ModuleCache -framework ScreenSaver macos/ClockPreferences.swift macos/ClockInstallation.swift tests/ClockInstallationTests.swift -o build/installation-tests
build/installation-tests
```

Проверки маршрутов настройки и размещения плавающей подсказки:

```sh
xcrun swiftc -swift-version 5 -module-cache-path build/ModuleCache macos/ClockSetupGuide.swift tests/ClockSetupGuideTests.swift -o build/setup-guide-tests
build/setup-guide-tests
xcrun swiftc -swift-version 5 -module-cache-path build/ModuleCache -framework AppKit macos/ClockSetupGuide.swift macos/SetupGuideView.swift macos/SetupCoach.swift tests/SetupCoachTests.swift -o build/setup-coach-tests
build/setup-coach-tests
```

Самопроверка приложения загружает настоящий `.saver` и проверяет воспроизведение, паузу, изменение размера и переходы видео через конец цикла. Упаковщик проверяет подписи и содержимое подключённого DMG:

```sh
"build/Cool Clock Preview.app/Contents/MacOS/CoolClockPreview" --self-test
./scripts/package-macos.sh
```

Результат упаковки: `dist/Cool-Clock-0.8.2-macOS.dmg` и `dist/SHA256SUMS`.

Для замера отрисовки и экспорта кадра:

```sh
"build/Cool Clock Preview.app/Contents/MacOS/CoolClockPreview" --benchmark /tmp/cool-clock-benchmark.json --seconds 40
"build/Cool Clock Preview.app/Contents/MacOS/CoolClockPreview" --render-preview /tmp/cool-clock.png --time 3.1
```

Интерфейс проверен на Apple Silicon с macOS 27.0.1. Работа на физическом Intel Mac, старых версиях macOS и установка на чистую систему отдельно не подтверждены.

## Windows

Нужны Python 3.12+ и Node.js 18+. Сборка работает на Apple Silicon macOS и на Windows x64/ARM64. Скрипт загружает закреплённые версии LLVM MinGW, WebView2 SDK и NSIS в `build/windows-tools`:

```sh
python3 scripts/fetch-media.py
python3 scripts/fetch-windows-dependencies.py
python3 scripts/build-windows.py
npm test
python3 -m unittest discover -s tests -p 'test_*.py'
```

Результат: `dist/Cool-Clock-0.9.1-Windows-Setup.exe` и `dist/Windows-SHA256SUMS`. В одном установщике находятся обе архитектуры и одна копия медиафайлов. Для своих путей к инструментам доступны параметры `--toolchain`, `--sdk` и `--nsis`; компилятор должен быть LLVM MinGW.

Режимы `Cool Clock.scr`:

| Аргументы | Действие |
| --- | --- |
| `/s` | Полноэкранная заставка на всех мониторах |
| `/p HWND` | Встроенный предпросмотр без звука |
| `/c` | Окно настройки звука |
| `--preview` | Отдельное окно часов; щелчок переключает звук |
| `--check-runtime` | Проверка наличия WebView2 Runtime |
| `--preview --smoke-report report.json --seconds 45` | Проверка воспроизведения с отчётом |

[Windows CI](https://github.com/pushipu/cool-clock/actions/runs/40644681911) проверяет x64 и ARM64: установку, отрисовку в трёх режимах, страницы мастера, обновление с активным предпросмотром и удаление. Отчёты сохраняются в артефактах запуска. Автозапуск после бездействия, вход после блокировки, звук и производительность на физическом оборудовании требуют отдельной проверки. Нажатия кнопок перехода к системным настройкам в этот прогон не входят.

Проверка совпадения геометрии использует снимки состояния, полученные из Swift. После намеренного изменения модели их можно обновить на Mac:

```sh
xcrun swiftc -swift-version 5 -module-cache-path build/ModuleCache macos/CloudScene.swift tests/ExportWindowsCloudScene.swift -o build/export-windows-scene
build/export-windows-scene
npm test
```

## Файлы проекта

- `macos/`: заставка, предпросмотр, установщик и отрисовка через Metal.
- `windows/`: Windows-приложение, установщик и отрисовка через WebView2.
- `clock-model.js` и `clock-glyphs.js`: расчёт времени и контуры цифр.
- `assets/rectangle-tracks.json`: геометрия прямоугольников.
- `assets/release-media.json`: адреса и контрольные суммы медиа.

[Источники материалов](../assets/CREDITS.md) · [Условия использования кода](../LICENSE)
