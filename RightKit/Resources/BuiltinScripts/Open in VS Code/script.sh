#!/bin/zsh
#
# 用 Visual Studio Code 打开选中项；在空白处右键时打开当前文件夹。
#
# RightKit 通过 XPC 服务执行脚本，继承的是 launchd 的最小 PATH，
# /opt/homebrew/bin 与 /usr/local/bin 都不在其中，因此这里显式补上。
# 本脚本只读：open 不会修改任何文件。

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

APP_NAME="Visual Studio Code"
APP_PATH="/Applications/${APP_NAME}.app"

# 没有参数（例如从空白处触发）时退回当前目录。
if [ "$#" -eq 0 ]; then
    if [ -z "$RIGHTKIT_DIR" ]; then
        echo "没有可打开的目标。" >&2
        exit 1
    fi
    set -- "$RIGHTKIT_DIR"
fi

if [ ! -d "$APP_PATH" ]; then
    # 没装 VS Code 就用默认程序打开，并说明原因；日志里能看到这一行。
    echo "未找到 ${APP_NAME}，改用默认程序打开：$*"
    open "$@"
    exit 0
fi

open -a "$APP_NAME" "$@"
