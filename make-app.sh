#!/bin/zsh
set -euo pipefail

swift build -c release

app_path=".build/SimpleAudioMonitor.app"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS"
mkdir -p "$app_path/Contents/Resources"
cp AppInfo.plist "$app_path/Contents/Info.plist"
cp .build/release/SimpleAudioMonitor "$app_path/Contents/MacOS/SimpleAudioMonitor"
cp Assets/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
# A stable designated requirement lets macOS associate microphone consent with
# this app across locally rebuilt versions. A normal distribution should use an
# Apple Development or Developer ID certificate instead of ad-hoc signing.
codesign --force --deep --sign - --identifier com.diego.simpleaudiomonitor \
  --requirements '=designated => identifier "com.diego.simpleaudiomonitor"' "$app_path"
echo "Created: $app_path"
