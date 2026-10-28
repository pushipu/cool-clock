#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
root="$PWD"
build="$root/build"
saver="$build/Cool Clock.saver"
preview="$build/Cool Clock Preview.app"
installer="$build/Cool Clock Installer.app"
mkdir -p "$build/objects" "$saver/Contents/MacOS" "$saver/Contents/Resources" "$preview/Contents/MacOS" "$preview/Contents/Resources" "$preview/Contents/PlugIns" "$installer/Contents/MacOS" "$installer/Contents/Resources"
for resource in assets/cloud-swift.mp4 assets/cloud-cirrus.mp4 assets/rectangle-tracks.json assets/ClockIcon.icns assets/thumbnail.png assets/thumbnail@2x.png macos/Clouds.metal; do
  if [[ ! -f "$resource" ]]; then
    echo "Missing live cloud resource: $resource" >&2
    exit 1
  fi
done
if [[ ! -f assets/audio/clock-minute.wav ]]; then
  echo 'Missing assets/audio/clock-minute.wav; minute audio is required.' >&2
  exit 1
fi
if [[ ! -f assets/CREDITS.md ]]; then
  echo 'Missing assets/CREDITS.md; video attribution must be bundled.' >&2
  exit 1
fi
python3 - "$root" <<'PY'
import json, pathlib, plistlib, re, shutil, sys
root = pathlib.Path(sys.argv[1])
source = (root / 'clock-glyphs.js').read_text()
glyphs = dict(re.findall(r"'([0-9])':\s*'([^']+)'", source))
assert len(glyphs) == 10, 'Expected all ten source glyphs'
for name, executable, identifier, kind in [
    ('Cool Clock.saver', 'CoolClock', 'ru.coolclock.screensaver', 'BNDL'),
    ('Cool Clock Preview.app', 'CoolClockPreview', 'ru.coolclock.preview', 'APPL'),
    ('Cool Clock Installer.app', 'CoolClockInstaller', 'ru.coolclock.installer', 'APPL')]:
    contents = root / 'build' / name / 'Contents'
    info = {'CFBundleExecutable': executable, 'CFBundleIdentifier': identifier,
            'CFBundleName': name.rsplit('.', 1)[0], 'CFBundlePackageType': kind,
            'CFBundleVersion': '17', 'CFBundleShortVersionString': '0.8.3',
            'CFBundleDevelopmentRegion': 'en', 'CFBundleLocalizations': ['en', 'ru'],
            'LSMinimumSystemVersion': '12.0', 'NSHighResolutionCapable': True,
            'CFBundleIconFile': 'ClockIcon.icns'}
    if kind == 'BNDL':
        for thumbnail in ['thumbnail.png', 'thumbnail@2x.png']:
            shutil.copy2(root / 'assets' / thumbnail, contents / 'Resources' / thumbnail)
        info['NSPrincipalClass'] = 'CoolClockSaverView'
    else:
        info['NSPrincipalClass'] = 'NSApplication'
    (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
    shutil.copy2(root / 'assets' / 'ClockIcon.icns', contents / 'Resources' / 'ClockIcon.icns')
    if name == 'Cool Clock Installer.app':
        shutil.copy2(root / 'LICENSE', contents / 'Resources' / 'LICENSE.txt')
    for obsolete in ['CloudBackground.mp4', 'OriginalClockFace.mp4']:
        (contents / 'Resources' / obsolete).unlink(missing_ok=True)
    if kind == 'BNDL':
        for source, target in [('assets/cloud-swift.mp4', 'CloudSwift.mp4'),
                               ('assets/cloud-cirrus.mp4', 'CloudCirrus.mp4'),
                               ('assets/rectangle-tracks.json', 'RectangleTracks.json'),
                               ('macos/Clouds.metal', 'Clouds.metal')]:
            shutil.copy2(root / source, contents / 'Resources' / target)
        shutil.copy2(root / 'assets' / 'audio' / 'clock-minute.wav', contents / 'Resources' / 'ClockMinute.wav')
        shutil.copy2(root / 'assets' / 'CREDITS.md', contents / 'Resources' / 'Credits.txt')
        (contents / 'Resources' / 'Glyphs.json').write_text(json.dumps(glyphs))
embedded_resources = root / 'build' / 'Cool Clock Preview.app' / 'Contents' / 'PlugIns' / 'Cool Clock.saver' / 'Contents' / 'Resources'
for obsolete in ['CloudBackground.mp4', 'OriginalClockFace.mp4']:
    (embedded_resources / obsolete).unlink(missing_ok=True)
PY
sdk="$(xcrun --sdk macosx --show-sdk-path)"
for arch in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -sdk "$sdk" -target "$arch-apple-macos12.0" \
    -module-cache-path "$build/ModuleCache" -module-name CoolClock -emit-library \
    -Xlinker -bundle \
    -framework AppKit -framework ScreenSaver -framework AVFoundation -framework MetalKit -framework CoreVideo \
    macos/ClockLanguage.swift macos/ClockFace.swift macos/CloudScene.swift macos/CloudRenderer.swift macos/CloudVideoPlayer.swift macos/ClockPreferences.swift macos/MinuteAudioPlayer.swift macos/CoolClockSaver.swift \
    -o "$build/objects/CoolClock-$arch"
  xcrun swiftc -swift-version 5 -O -sdk "$sdk" -target "$arch-apple-macos12.0" \
    -module-cache-path "$build/ModuleCache" -module-name CoolClockPreview \
    -framework AppKit -framework ScreenSaver -framework AVFoundation -framework MetalKit -framework CoreVideo \
    macos/ClockLanguage.swift macos/ClockFace.swift macos/CloudScene.swift macos/CloudRenderer.swift macos/CloudVideoPlayer.swift macos/ClockPreferences.swift macos/MinuteAudioPlayer.swift macos/Preview.swift \
    -o "$build/objects/CoolClockPreview-$arch"
  xcrun swiftc -swift-version 5 -O -sdk "$sdk" -target "$arch-apple-macos12.0" \
    -module-cache-path "$build/ModuleCache" -module-name CoolClockInstaller \
    -framework AppKit -framework ScreenSaver \
    macos/ClockLanguage.swift macos/ClockPreferences.swift macos/ClockInstallation.swift macos/ClockSetupGuide.swift macos/SetupGuideView.swift macos/SetupCoach.swift macos/Installer.swift \
    -o "$build/objects/CoolClockInstaller-$arch"
done
xcrun lipo -create "$build/objects/CoolClock-arm64" "$build/objects/CoolClock-x86_64" -output "$saver/Contents/MacOS/CoolClock"
xcrun lipo -create "$build/objects/CoolClockPreview-arm64" "$build/objects/CoolClockPreview-x86_64" -output "$preview/Contents/MacOS/CoolClockPreview"
xcrun lipo -create "$build/objects/CoolClockInstaller-arm64" "$build/objects/CoolClockInstaller-x86_64" -output "$installer/Contents/MacOS/CoolClockInstaller"
codesign --force --sign - "$saver"
ditto "$saver" "$preview/Contents/PlugIns/Cool Clock.saver"
codesign --force --sign - "$preview"
ditto "$preview" "$installer/Contents/Resources/Cool Clock Preview.app"
codesign --force --sign - "$installer"
codesign --verify --strict "$saver"
codesign --verify --deep --strict "$preview"
codesign --verify --deep --strict "$installer"
printf 'Built:\n%s\n%s\n%s\n' "$saver" "$preview" "$installer"
