#!/bin/zsh
set -eu
cd "${0:A:h}/.."
swift build -c release
app="$PWD/output/ClaudeSentinel.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/ClaudeSentinel "$app/Contents/MacOS/ClaudeSentinel"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ClaudeSentinel</string>
<key>CFBundleIdentifier</key><string>local.claude-sentinel.app</string>
<key>CFBundleName</key><string>Claude 小哨兵</string>
<key>CFBundleDisplayName</key><string>Claude 小哨兵</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
print "Built: $app"
