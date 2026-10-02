#!/bin/zsh
#
# 用 Python 运行选中的 .py 文件。
#
# RightKit 通过 XPC 服务执行脚本，继承的是 launchd 的最小环境，
# /opt/homebrew/bin 与 /usr/local/bin 都不在其中，因此这里显式补上。
# 指定的 python3 与输出都会写进日志，主 App 会把最后一行放进通知里。

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

if [ "$#" -eq 0 ]; then
    echo "没有可运行的文件。" >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "找不到 python3，请先安装 Python 或 Xcode 命令行工具。" >&2
    exit 1
fi

echo "解释器：$(command -v python3)"
echo "版本：$(python3 --version 2>&1)"

exit_code=0
for file in "$@"; do
    echo
    echo "==> 运行 ${file}"
    # 在脚本自己所在的目录里执行，脚本里的相对路径才符合直觉。
    (
        cd "$(dirname "${file}")" || exit 1
        python3 "$(basename "${file}")"
    ) || exit_code=$?
done

exit "${exit_code}"
