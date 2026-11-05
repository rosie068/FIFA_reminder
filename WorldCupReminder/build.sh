#!/bin/zsh
# Builds World Cup Reminder.app
set -euo pipefail
cd "$(dirname "$0")"

APP="build/World Cup Reminder.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Icon: render ⚽ emoji -> iconset -> icns
mkdir -p build/AppIcon.iconset
swift make_icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# Compile
swiftc -O -parse-as-library Sources/main.swift -o "$APP/Contents/MacOS/WorldCupReminder"

# Bundle
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/matches.json "$APP/Contents/Resources/matches.json"
cp Resources/goal.png "$APP/Contents/Resources/goal.png"

# Ad-hoc sign (required for UserNotifications)
codesign --force --deep --sign - "$APP"

echo "Built: $PWD/$APP"
