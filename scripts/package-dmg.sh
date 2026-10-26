#!/bin/zsh
set -eu
cd "${0:A:h}/.."
# The ZIP packager also checks the application bundle allowlist and signature.
./scripts/package.sh
python_bin="${DMG_PYTHON:-$PWD/.build/dmg-tools/bin/python3}"
if [[ ! -x "$python_bin" ]]; then
  print -u2 'Install DMG build dependencies first: python3 -m venv .build/dmg-tools && .build/dmg-tools/bin/pip install -r scripts/requirements-dmg.txt'
  exit 1
fi
app="$PWD/output/ClaudeSentinel.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
arch="$(/usr/bin/lipo -archs "$app/Contents/MacOS/ClaudeSentinel")"
if [[ "$arch" == *' '* ]]; then arch=universal; fi
if [[ "${SIGN_IDENTITY:--}" == '-' ]]; then kind=adhoc; else kind=developer-id; fi
name="ClaudeSentinel-$version-macos-$arch-$kind.dmg"
volume='/Volumes/Claude Sentinel'
if [[ -e "$volume" ]]; then print -u2 'Eject the existing Claude Sentinel volume before packaging.'; exit 1; fi
work="$(mktemp -d "$PWD/.build/dmg.XXXXXX")"
mounted=false
cleanup() {
  if $mounted; then /usr/bin/hdiutil detach "$volume" -quiet || true; fi
  # Only the task-created temporary directory is removed.
  /bin/rm -rf "$work"
}
trap cleanup EXIT
stage="$work/stage"
mkdir -p "$stage/.background" "$stage/.fseventsd"
touch "$stage/.metadata_never_index" "$stage/.fseventsd/no_log"
/usr/bin/ditto --norsrc --noextattr "$app" "$stage/ClaudeSentinel.app"
ln -s /Applications "$stage/Applications"
cp "$app/Contents/Resources/AppIcon.icns" "$stage/.VolumeIcon.icns"
"$app/Contents/MacOS/ClaudeSentinel" --render-dmg-background "$stage/.background/space-station.png"
/usr/bin/hdiutil create -quiet -volname 'Claude Sentinel' -srcfolder "$stage" -nospotlight -anyowners -fs HFS+ -format UDRW "$work/writable.dmg"
/usr/bin/hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$volume" "$work/writable.dmg"
mounted=true
"$python_bin" scripts/configure-dmg.py "$volume"
/usr/bin/SetFile -a C "$volume"
"$python_bin" scripts/verify-dmg.py "$volume"
/usr/bin/hdiutil detach -quiet "$volume"
mounted=false
/usr/bin/hdiutil convert -quiet "$work/writable.dmg" -format UDZO -imagekey zlib-level=9 -o "$work/$name"
/usr/bin/hdiutil verify "$work/$name"
cp "$work/$name" "output/$name"
(cd output && /usr/bin/shasum -a 256 "$name" > "$name.sha256")
print "DMG: $PWD/output/$name"
print 'The installer contains a /Applications shortcut; no settings or diagnostic history are included.'
