#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
saver="$root/build/Cool Clock.saver"
preview="$root/build/Cool Clock Preview.app"
embedded="$preview/Contents/PlugIns/Cool Clock.saver"
installer="$root/build/Cool Clock Installer.app"

version=$(python3 - "$saver" "$preview" "$embedded" "$installer" <<'PY'
import hashlib, pathlib, plistlib, re, sys
bundles = [pathlib.Path(p) for p in sys.argv[1:]]
infos = [plistlib.loads((p / 'Contents/Info.plist').read_bytes()) for p in bundles]
versions = {(p['CFBundleShortVersionString'], p['CFBundleVersion']) for p in infos}
assert len(versions) == 1, 'Build, preview and embedded saver versions differ; rebuild first'
version, build = versions.pop()
assert re.fullmatch(r'[0-9]+(?:\.[0-9]+){2}', version), 'Expected a three-part release version'
def manifest(bundle):
    return {str(p.relative_to(bundle)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in bundle.rglob('*') if p.is_file()}
assert manifest(bundles[0]) == manifest(bundles[2]), 'Embedded saver differs from build'
assert manifest(bundles[1]) == manifest(bundles[3] / 'Contents/Resources/Cool Clock Preview.app'), 'Installer payload differs from preview'
print(version)
PY
)
codesign --verify --strict "$saver"
codesign --verify --deep --strict "$preview"
codesign --verify --deep --strict "$installer"

stage=$(mktemp -d "${TMPDIR:-/tmp}/cool-clock-release.XXXXXX")
mounted=no
cleanup() {
  if [[ "$mounted" == yes ]]; then
    if ! hdiutil detach "$stage/mounted" >/dev/null; then
      printf 'Could not detach release image; temporary files retained at %s\n' "$stage" >&2
      return
    fi
  fi
  rm -rf "$stage"
}
trap cleanup EXIT
mkdir -p "$stage/payload" "$stage/output" "$stage/mounted" "$root/dist"

ditto "$installer" "$stage/payload/Cool Clock Installer.app"

dmg="Cool-Clock-$version-macOS.dmg"
hdiutil create -quiet -format UDZO -volname "Cool Clock $version" \
  -srcfolder "$stage/payload" "$stage/output/$dmg"
hdiutil verify "$stage/output/$dmg"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$stage/mounted" "$stage/output/$dmg"
mounted=yes
codesign --verify --deep --strict "$stage/mounted/Cool Clock Installer.app"
python3 - "$installer" "$stage/mounted/Cool Clock Installer.app" <<'PY'
import hashlib, pathlib, sys
def manifest(bundle):
    return {str(p.relative_to(bundle)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in bundle.rglob('*') if p.is_file() and not p.name.startswith('._')}
expected = manifest(pathlib.Path(sys.argv[1]))
assert manifest(pathlib.Path(sys.argv[2])) == expected, 'Mounted installer differs from build'
PY
hdiutil detach "$stage/mounted" >/dev/null
mounted=no
(
  cd "$stage/output"
  shasum -a 256 "$dmg" > SHA256SUMS
  shasum -a 256 -c SHA256SUMS
)
mv "$stage/output/$dmg" "$stage/output/SHA256SUMS" "$root/dist/"
printf 'Verified release files:\n%s\n%s\n' "$root/dist/$dmg" "$root/dist/SHA256SUMS"
