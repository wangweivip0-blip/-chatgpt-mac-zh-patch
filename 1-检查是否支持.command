#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}"
result=0
trap 'result=$?; print ""; read -r "?按回车关闭窗口…"; exit "$result"' EXIT
source_app="${1:-}"
if [[ -z "$source_app" ]]; then
  for candidate in /Applications/ChatGPT.app /Applications/Codex.app "$HOME/Applications/ChatGPT.app" "$HOME/Applications/Codex.app"; do
    if [[ -d "$candidate" ]]; then source_app="$candidate"; break; fi
  done
fi
[[ -n "$source_app" && -d "$source_app" ]] || { print "找不到应用，请在终端传入 .app 完整路径。"; exit 1; }
source_app="${source_app:A}"
identity=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist")
[[ "$identity" == com.openai.codex ]] || { print "所选应用不是 com.openai.codex。"; exit 1; }
/usr/bin/perl ./locale-tool.pl --check "$source_app"
if /usr/bin/perl ./patch-state.pl "$source_app"; then
  /usr/bin/codesign --verify --deep --strict "$source_app"
  print "ChatGPT 已有中文修复，签名校验通过。"
else
  state_result=$?
  (( state_result == 1 )) || { print "补丁状态未知。"; exit 1; }
  /usr/bin/perl ./patch-asar.pl --inspect "$source_app"
fi
print "只读检查完成。"
