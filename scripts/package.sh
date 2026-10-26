#!/bin/zsh
set -eu
cd "${0:A:h}/.."
./scripts/build.sh
app="$PWD/output/ClaudeSentinel.app"
# An explicit bundle allowlist prevents accidental inclusion of local settings or logs.
for item in "$app"/Contents/**/*(DN@); do
  print -u2 "Refusing to package a symlink: ${item#$app/}"
  exit 1
done
for item in "$app"/Contents/**/*(DN.); do
  case "${item#$app/}" in
    Contents/Info.plist|Contents/MacOS/ClaudeSentinel|Contents/Resources/AppIcon.icns|Contents/_CodeSignature/CodeResources) ;;
    *) print -u2 "Unexpected bundle file; inspect before sharing: ${item#$app/}"; exit 1 ;;
  esac
done
archs="$(/usr/bin/lipo -archs "$app/Contents/MacOS/ClaudeSentinel")"
case "$archs" in
  arm64) arch=arm64 ;;
  x86_64) arch=x86_64 ;;
  'arm64 x86_64'|'x86_64 arm64') arch=universal ;;
  *) print -u2 "Unsupported binary architectures: $archs"; exit 1 ;;
esac
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
if [[ "${SIGN_IDENTITY:--}" == '-' ]]; then kind=adhoc; else kind=developer-id; fi
archive="ClaudeSentinel-$version-macos-$arch-$kind.zip"
/usr/bin/ditto -c -k --keepParent --norsrc --noextattr "$app" "$PWD/output/$archive"
(cd output && /usr/bin/shasum -a 256 "$archive" > "$archive.sha256")
print "Archive: $PWD/output/$archive"
print "Checksum: $PWD/output/$archive.sha256"
if [[ "$kind" == adhoc ]]; then
  print 'Local test package only: ad-hoc signed, not Apple-notarized.'
else
  print 'Developer ID signed only: notarize and staple before general distribution.'
fi
