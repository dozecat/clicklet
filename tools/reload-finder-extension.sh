#!/bin/bash
#
# Reload the Clicklet Finder extension after rebuilding it.
#
# Why this is needed: Finder hosts a Finder Sync extension in its own process and
# keeps that process alive. Rebuilding the app replaces the binary on disk, but
# the already-running process keeps executing the old code until it is unloaded
# and Finder starts it again. Symptoms of forgetting this: the menu still shows
# old titles, or a fixed bug appears to still be broken.
#
# Usage:  tools/reload-finder-extension.sh
#
set -euo pipefail

EXTENSION_ID="com.dozecat.Clicklet.FinderExtension"
APP_ID="com.dozecat.Clicklet"

echo "==> Quitting Clicklet (rebuilt by Xcode next time you run it)"
osascript -e "tell application id \"$APP_ID\" to quit" >/dev/null 2>&1 ||
    killall Clicklet >/dev/null 2>&1 || true

echo "==> Dropping the running extension process"
# Finder relaunches it on the next right-click, picking up the new binary.
pkill -x FinderExtension >/dev/null 2>&1 || true

echo "==> Making sure the extension is enabled"
if ! pluginkit -e use -i "$EXTENSION_ID" >/dev/null 2>&1; then
    echo "    pluginkit refused; toggle it manually in"
    echo "    System Settings > General > Login Items & Extensions > Finder Extensions"
fi

echo "==> Restarting Finder"
killall Finder >/dev/null 2>&1 || true

echo
echo "Done. Watch the extension work with:"
found=0
for log in "$HOME"/Library/Group\ Containers/*group.com.dozecat.Clicklet/Logs/clicklet.log; do
    if [ -f "$log" ]; then
        echo "    tail -f \"$log\""
        found=1
    fi
done
if [ "$found" -eq 0 ]; then
    echo "    (no diagnostics log yet; run the app once to create it)"
fi
