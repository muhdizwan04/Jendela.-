#!/bin/zsh

set -e

PROJECT_DIR="${0:A:h}"
DERIVED="/tmp/widgetmac-dd"
APP_DIR="$PROJECT_DIR/Jendela.app"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# The Xcode project is generated from Support/generate_project.rb, so adding a
# source file only means re-running it — nothing is hand-maintained in the
# .xcodeproj. SwiftPM can still build the app alone (`swift build`), but it
# cannot produce the widget extension, which must be an .appex.
if [[ ! -d "$PROJECT_DIR/Jendela.xcodeproj" ]]; then
  ruby "$PROJECT_DIR/Support/generate_project.rb"
fi

xcodebuild -project "$PROJECT_DIR/Jendela.xcodeproj" \
  -scheme Jendela -configuration Debug \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates build

# `open` only activates an already-running instance, so quit first or you keep
# looking at the previous build.
osascript -e 'quit app "Jendela"' >/dev/null 2>&1 || true
pkill -x Jendela >/dev/null 2>&1 || true

rm -rf "$APP_DIR"
cp -R "$DERIVED/Build/Products/Debug/Jendela.app" "$APP_DIR"

# WidgetKit finds the extension through LaunchServices, and a stale record
# pointing at DerivedData will shadow this copy.
"$LSREG" -u "$DERIVED/Build/Products/Debug/Jendela.app" >/dev/null 2>&1 || true
"$LSREG" -f -R "$APP_DIR"

open "$APP_DIR"
