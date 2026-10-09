#!/bin/zsh
#
# Runs the selected .py files with Python.
#
# Clicklet runs scripts through an XPC service, so the environment inherited is
# launchd's minimal one: /opt/homebrew/bin and /usr/local/bin are missing from it,
# hence the explicit setting below. The python3 that runs and its output both go to
# the log, and the main app puts the last line into a notification.

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
    # Run from the script's own directory, so relative paths inside it behave as expected.
    (
        cd "$(dirname "${file}")" || exit 1
        python3 "$(basename "${file}")"
    ) || exit_code=$?
done

exit "${exit_code}"
