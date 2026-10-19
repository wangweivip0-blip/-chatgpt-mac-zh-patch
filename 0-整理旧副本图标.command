#!/bin/zsh
set -euo pipefail
CODEX_ZH_ENTRY_SCRIPT="${0:A}"
cd -- "${0:A:h}"
source ./common.zsh
trap 'result=$?; release_lock; print ""; read -r "?按回车关闭窗口…"; exit "$result"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
if /usr/bin/pgrep -f '/Contents/MacOS/(Codex|ChatGPT)( |$)' >/dev/null; then
  print "请先完全退出 ChatGPT（包括可能还在运行的旧副本）。"
  exit 1
else
  probe_result=$?
  (( probe_result == 1 )) || { print "无法检查应用进程，停止。"; exit 1; }
fi
if (( EUID != 0 )); then
  elevate_for_install
fi
if [[ -d /Applications/ChatGPT.app ]]; then
  acquire_lock /Applications/ChatGPT.app
elif [[ -d /Applications/Codex.app ]]; then
  acquire_lock /Applications/Codex.app
fi
user_home="${CODEX_ZH_ORIGINAL_HOME:-$HOME}"
history="$user_home/Library/Application Support/ChatGPT-中文工具/历史副本.noindex"
/usr/bin/perl ./organize-old-copies.pl --apply "${PWD:h}" "$history" /Applications "$user_home/Applications"
print "现在请从‘应用程序’中打开 ChatGPT。不要打开旧备份。"
