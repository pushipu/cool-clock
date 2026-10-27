#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
saver="$root/build/Cool Clock.saver"
preview="$root/build/Cool Clock Preview.app"
embedded="$preview/Contents/PlugIns/Cool Clock.saver"

version=$(python3 - "$saver" "$preview" "$embedded" <<'PY'
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
print(version)
PY
)
codesign --verify --strict "$saver"
codesign --verify --deep --strict "$preview"

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

ditto "$preview" "$stage/payload/Cool Clock Preview.app"
ln -s 'Cool Clock Preview.app/Contents/PlugIns/Cool Clock.saver' "$stage/payload/Cool Clock.saver"
ln -s /Applications "$stage/payload/Applications"
cp "$root/docs/INSTALL.md" "$stage/payload/Установка.txt"
cp "$root/assets/CREDITS.md" "$stage/payload/Credits.txt"
if [[ -f "$root/LICENSE" ]]; then cp "$root/LICENSE" "$stage/payload/LICENSE.txt"; fi

dmg="Cool-Clock-$version-macOS.dmg"
zip="Cool-Clock-$version-saver.zip"
ditto -c -k --sequesterRsrc --keepParent "$saver" "$stage/output/$zip"
hdiutil create -quiet -format UDZO -volname "Cool Clock $version" \
  -srcfolder "$stage/payload" "$stage/output/$dmg"
hdiutil verify "$stage/output/$dmg"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$stage/mounted" "$stage/output/$dmg"
mounted=yes
[[ "$(readlink "$stage/mounted/Cool Clock.saver")" == 'Cool Clock Preview.app/Contents/PlugIns/Cool Clock.saver' ]]
[[ -d "$stage/mounted/Cool Clock.saver" ]]
codesign --verify --strict "$stage/mounted/Cool Clock.saver"
codesign --verify --deep --strict "$stage/mounted/Cool Clock Preview.app"
python3 - "$saver" "$stage/mounted/Cool Clock.saver" "$stage/output/$zip" <<'PY'
import hashlib, pathlib, sys, zipfile
def manifest(bundle):
    return {str(p.relative_to(bundle)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in bundle.rglob('*') if p.is_file() and not p.name.startswith('._')}
expected = manifest(pathlib.Path(sys.argv[1]))
assert manifest(pathlib.Path(sys.argv[2])) == expected, 'Mounted saver differs from build'
with zipfile.ZipFile(sys.argv[3]) as archive:
    assert archive.testzip() is None, 'ZIP integrity check failed'
    prefix = 'Cool Clock.saver/'
    actual = {name[len(prefix):]: hashlib.sha256(archive.read(name)).hexdigest()
              for name in archive.namelist() if name.startswith(prefix)
              and not name.endswith('/') and not pathlib.PurePosixPath(name).name.startswith('._')}
assert actual == expected, 'ZIP saver differs from build'
PY
hdiutil detach "$stage/mounted" >/dev/null
mounted=no
(
  cd "$stage/output"
  shasum -a 256 "$dmg" "$zip" > SHA256SUMS
  shasum -a 256 -c SHA256SUMS
)
mv "$stage/output/$dmg" "$stage/output/$zip" "$stage/output/SHA256SUMS" "$root/dist/"
printf 'Verified release files:\n%s\n%s\n%s\n' "$root/dist/$dmg" "$root/dist/$zip" "$root/dist/SHA256SUMS"
