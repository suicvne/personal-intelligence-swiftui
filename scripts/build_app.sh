#!/bin/sh
# Build build/Intel.app from this package: release build, a minimal Info.plist, ad-hoc signature.
#
#   scripts/build_app.sh && open build/Intel.app
#
# Copy build/Intel.app to /Applications to keep it.
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product Intel
binary="$(swift build -c release --show-bin-path)/Intel"

app="build/Intel.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Intel"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>        <string>local.intel.gui</string>
    <key>CFBundleName</key>              <string>Intel</string>
    <key>CFBundleDisplayName</key>       <string>Intel</string>
    <key>CFBundleExecutable</key>        <string>Intel</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <!-- Plain http to the intel API: loopback by default, a LAN host if you move the service. -->
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key><true/>
    </dict>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Intel connects to your intel service when it runs on another machine on your network.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$app"
echo "Built $app"
