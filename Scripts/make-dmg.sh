#!/bin/bash
#
# Build a Clicklet DMG with the window layout this project ships.
#
#   Scripts/make-dmg.sh <Clicklet.app> <output.dmg>
#
# Why this is not a one-liner
# ---------------------------
# The layout — window size, icon size, icon positions and the background picture —
# lives in the image's .DS_Store, and Finder only writes that while the image is
# actually mounted and its window is on screen. So the flow has to be:
#
#   1. build a writable image of the staging folder
#   2. mount it and let Finder set the window up (AppleScript)
#   3. detach, then convert to a compressed read-only image
#
# `hdiutil create -srcfolder ... -format UDZO` in one step cannot do this, and
# `hdiutil makehybrid` produces something Finder will not mount on double-click at
# all — the resulting file looks like a disk image but is an Apple Driver Map.
#
# The background's pixel size IS the window size
# ----------------------------------------------
# Finder draws an icon-view background at 1:1 pixels, not scaled to the window. A
# 1120x720 picture therefore needs a 1120x720 window, or the picture is cropped at
# the right and bottom. The numbers below and dmg-background.png must agree.

set -euo pipefail

APP="${1:?usage: make-dmg.sh <Clicklet.app> <output.dmg>}"
OUT="${2:?usage: make-dmg.sh <Clicklet.app> <output.dmg>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKGROUND="$SCRIPT_DIR/dmg-background.png"
VOLNAME="Clicklet"

# Keep these in step with dmg-background.png (1120x720 at 2x, so 560x360 points).
WIN_X=140; WIN_Y=100; WIN_W=1120; WIN_H=720
ICON=256
APP_POS_X=280;  APP_POS_Y=430
LINK_POS_X=840; LINK_POS_Y=430

[ -d "$APP" ] || { echo "error: no app bundle at $APP" >&2; exit 1; }
[ -f "$BACKGROUND" ] || { echo "error: missing $BACKGROUND" >&2; exit 1; }

WORK="$(mktemp -d)"
RW="$WORK/Clicklet-rw.dmg"
STAGE="$WORK/stage"
MOUNT=""

cleanup() {
    if [ -n "$MOUNT" ]; then
        hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "==> staging"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$BACKGROUND" "$STAGE/.background/background.png"

echo "==> writing a writable image"
rm -f "$RW"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDRW "$RW" >/dev/null
[ -f "$RW" ] || { echo "error: could not create the writable image" >&2; exit 1; }

echo "==> mounting"
MOUNT="$(hdiutil attach "$RW" -nobrowse | grep -o "/Volumes/$VOLNAME.*" | head -1)"
[ -n "$MOUNT" ] || { echo "error: could not mount the writable image" >&2; exit 1; }

echo "==> asking Finder to lay the window out"
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {$WIN_X, $WIN_Y, $((WIN_X + WIN_W)), $((WIN_Y + WIN_H))}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to $ICON
        set text size of theViewOptions to 15
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "Clicklet.app" of container window to {$APP_POS_X, $APP_POS_Y}
        set position of item "Applications" of container window to {$LINK_POS_X, $LINK_POS_Y}
        update without registering applications
        delay 1
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

sync
sleep 1

echo "==> detaching"
hdiutil detach "$MOUNT" >/dev/null 2>&1 || hdiutil detach "$MOUNT" -force >/dev/null 2>&1
MOUNT=""

echo "==> converting to a compressed read-only image"
rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -o "$OUT" >/dev/null

# A file that is not a UDIF image is not a DMG: Finder will refuse to open it, and
# the failure is silent for whoever downloaded it. Catch that here instead.
CLASS="$(hdiutil imageinfo "$OUT" | awk -F': ' '/^Class Name:/ {print $2; exit}')"
if [ "$CLASS" != "CUDIFDiskImage" ]; then
    echo "error: $OUT is not a UDIF disk image (got '${CLASS:-nothing}')." >&2
    echo "error: Finder would not open it on double-click, so it is being removed." >&2
    rm -f "$OUT"
    exit 1
fi

shasum -a 256 "$OUT" | awk -v name="$(basename "$OUT")" '{print $1"  "name}' > "$OUT.sha256"

echo "==> $OUT"
echo "    $(hdiutil imageinfo "$OUT" | awk -F': ' '/^Format:/ {print $2; exit}'), $(du -h "$OUT" | cut -f1)"
