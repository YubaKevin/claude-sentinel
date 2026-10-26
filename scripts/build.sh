#!/bin/zsh
set -eu
cd "${0:A:h}/.."
version="${VERSION:-0.1.0}"
build_number="${BUILD_NUMBER:-1}"
identity="${SIGN_IDENTITY:--}"
if ! [[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' && "$build_number" =~ '^[1-9][0-9]*$' ]]; then
  print -u2 'VERSION must be major.minor.patch; BUILD_NUMBER must be a positive integer.'
  exit 1
fi
# Ship the release executable without local debug symbols.
build_args=(-c release)
swift build "${build_args[@]}"
bin_dir="$(swift build "${build_args[@]}" --show-bin-path)"
app="$PWD/output/ClaudeSentinel.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/ClaudeSentinel" "$app/Contents/MacOS/ClaudeSentinel"
/usr/bin/strip -S "$app/Contents/MacOS/ClaudeSentinel"
iconset="$PWD/.build/AppIcon.iconset"
"$bin_dir/ClaudeSentinel" --render-app-icon "$iconset"
/usr/bin/iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ClaudeSentinel</string>
<key>CFBundleIdentifier</key><string>local.claude-sentinel.app</string>
<key>CFBundleName</key><string>Claude 小哨兵</string>
<key>CFBundleDisplayName</key><string>Claude 小哨兵</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleVersion</key><string>$build_number</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ "$identity" == '-' ]]; then
  codesign --force --sign - "$app"
else
  codesign --force --options runtime --timestamp --sign "$identity" "$app"
fi
codesign --verify --strict --verbose=2 "$app"
print "Built: $app"
