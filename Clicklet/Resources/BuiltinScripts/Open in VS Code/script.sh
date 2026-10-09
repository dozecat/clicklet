#!/bin/zsh
#
# Opens the selection in Visual Studio Code; from empty space, the current folder.
#
# RightKit runs scripts through an XPC service, so the PATH inherited is launchd's
# minimal one: /opt/homebrew/bin and /usr/local/bin are missing from it, hence the
# explicit setting below. This script only reads — `open` changes nothing.

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

APP_NAME="Visual Studio Code"
APP_PATH="/Applications/${APP_NAME}.app"

# With no arguments — triggered from empty space, say — fall back to the current folder.
if [ "$#" -eq 0 ]; then
    if [ -z "$RIGHTKIT_DIR" ]; then
        echo "没有可打开的目标。" >&2
        exit 1
    fi
    set -- "$RIGHTKIT_DIR"
fi

if [ ! -d "$APP_PATH" ]; then
    # Without VS Code, fall back to the default handler and say why; this line reaches the log.
    echo "未找到 ${APP_NAME}，改用默认程序打开：$*"
    open "$@"
    exit 0
fi

open -a "$APP_NAME" "$@"
