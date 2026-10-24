#!/bin/zsh
set -euo pipefail
CODEX_ZH_ENTRY_SCRIPT="${0:A}"
cd -- "${0:A:h}"
if [[ "${CODEX_ZH_LOGGING:-0}" != 1 ]]; then
  export CODEX_ZH_LOGGING=1
  log_file="$PWD/运行日志-$(/bin/date +%Y%m%d-%H%M%S)-$$.txt"
  exec > >(/usr/bin/tee -a "$log_file") 2>&1
  print "本次运行日志：$log_file"
fi
result=0
source ./common.zsh
patch_started=0
backup_app=""
source_app=""
finish() {
  result=$?
  trap - EXIT
  if (( result != 0 && patch_started == 1 )); then
    print "修复未完成，正在从完整备份恢复原应用…"
    if ! restore_application "$source_app" "$backup_app"; then
      print "自动恢复失败。请保留备份目录，按说明手动恢复：$backup_app"
    fi
  fi
  release_lock
  print ""
  read -r '?按回车关闭窗口…'
  exit "$result"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
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
if /usr/bin/pgrep -f '/Contents/MacOS/(Codex|ChatGPT)( |$)' >/dev/null; then
  print "请按 Command-Q 完全退出 Codex / ChatGPT 后再运行。"
  exit 1
else
  probe_result=$?
  (( probe_result == 1 )) || { print "无法查询应用进程，停止。"; exit 1; }
fi
if /usr/bin/perl ./patch-state.pl "$source_app"; then
  /usr/bin/codesign --verify --deep --strict "$source_app"
  if [[ ! -w "$source_app" || ! -w "${source_app:h}" ]]; then
    elevate_for_install "$source_app"
  fi
  acquire_lock "$source_app"
  /usr/bin/perl ./patch-state.pl "$source_app"
  run_user_config --apply "$source_app"
  print "ChatGPT 已应用中文修复且签名有效，无需重复修改或再建备份。"
  exit 0
else
  state_result=$?
  (( state_result == 1 )) || { print "无法识别补丁状态，停止修改。"; exit 1; }
fi
if [[ ! -w "$source_app" || ! -w "${source_app:h}" ]]; then
  elevate_for_install "$source_app"
fi
if (( EUID == 0 )); then
  [[ "${CODEX_ZH_ORIGINAL_UID:-}" == <-> && "${CODEX_ZH_ORIGINAL_GID:-}" == <-> && "$CODEX_ZH_ORIGINAL_UID" != 0 ]] || { print "请由普通用户双击运行本工具，不要手动以 root 启动。"; exit 1; }
fi
acquire_lock "$source_app"
run_user_config --check "$source_app"
/usr/bin/perl ./patch-asar.pl --inspect "$source_app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$source_app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$source_app/Contents/Info.plist")
print "待修复应用：$source_app；版本：$version/$build"
/usr/bin/codesign --verify --deep --strict "$source_app" || { print "源应用签名校验失败，未修改。请先安装可信官方版本。"; exit 1; }
required_kb=$(/usr/bin/du -sk "$source_app" | /usr/bin/awk '{print $1}')
available_kb=$(/bin/df -Pk "$PWD" | /usr/bin/awk 'END {print $4}')
[[ "$required_kb" == <-> && "$available_kb" == <-> ]] || { print "无法确认备份磁盘空间，未修改。"; exit 1; }
(( available_kb > required_kb + 524288 )) || { print "备份所在磁盘空间不足；请至少留出应用大小加 512 MB。"; exit 1; }
backup_dir="$PWD/备份-$(/bin/date +%Y%m%d-%H%M%S)-$$.noindex"
/bin/mkdir -m 700 "$backup_dir"
if (( EUID == 0 )); then
  /usr/sbin/chown "$CODEX_ZH_ORIGINAL_UID:$CODEX_ZH_ORIGINAL_GID" "$backup_dir"
  print "管理员授权备份" > "$backup_dir/admin-required"
fi
backup_app="$backup_dir/${source_app:t}"
print "正在完整备份原应用，约需 2 GB 空间…"
/usr/bin/ditto "$source_app" "$backup_app"
/usr/bin/perl ./verify-tree.pl --record "$source_app" "$backup_app.manifest.json"
/usr/bin/perl ./verify-tree.pl --verify "$backup_app" "$backup_app.manifest.json"
/usr/bin/perl ./patch-asar.pl --inspect "$backup_app"
print -r -- "$source_app" > "$backup_dir/source-path.txt"
print -r -- "$version/$build" > "$backup_dir/version.txt"
print -r -- "$backup_dir" > ./latest-backup.txt
patch_started=1
/usr/bin/perl ./patch-asar.pl --patch "$source_app" "$backup_app"
print "正在清理签名不允许的 FinderInfo/ResourceFork 元数据…"
/usr/bin/perl ./clean-signing-metadata.pl "$source_app"
/usr/bin/codesign --force --deep --sign - --timestamp=none "$source_app"
/usr/bin/codesign --verify --deep --strict "$source_app"
run_user_config --apply "$source_app"
/usr/bin/perl ./verify-tree.pl --record "$source_app" "$backup_dir/patched.manifest.json"
patch_started=0
print "原位修复完成。直接打开原来的应用即可。"
print "完整备份：$backup_app"
print "本地重签可能影响钥匙串、权限与自动更新，详见说明。"
