#!/bin/zsh
# Regenerates Support/AppIcon.icns from Support/make_icon.swift.
set -e
HERE="${0:A:h}"
WORK="$(mktemp -d)"
swiftc -O "$HERE/make_icon.swift" -o "$WORK/makeicon"
"$WORK/makeicon" "$WORK/AppIcon.iconset"
iconutil -c icns "$WORK/AppIcon.iconset" -o "$HERE/AppIcon.icns"
rm -rf "$WORK"
echo "wrote $HERE/AppIcon.icns"
