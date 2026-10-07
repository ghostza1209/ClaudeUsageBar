#!/bin/sh
# Builds release, assembles an ad-hoc signed ClaudeUsageBar.app under .build/ and opens it.
# NO_OPEN=1 stops after signing (used by package.sh). This is the only supported way to run the app (see docs/adr/0001).
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product ClaudeUsageBar
app=.build/ClaudeUsageBar.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
bin=$(swift build -c release --show-bin-path)
cp "$bin/ClaudeUsageBar" "$app/Contents/MacOS/"
cp -R "$bin/ClaudeUsageBar_UsageCore.bundle" "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>ClaudeUsageBar</string>
	<key>CFBundleIdentifier</key><string>com.ysz.ClaudeUsageBar</string>
	<key>CFBundleName</key><string>ClaudeUsageBar</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.1</string>
	<key>LSUIElement</key><true/>
</dict>
</plist>
EOF
codesign --force -s - "$app"
[ -n "${NO_OPEN:-}" ] && exit 0
pkill -x ClaudeUsageBar || true
open "$app"
