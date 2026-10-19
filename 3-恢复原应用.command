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
trap 'result=$?; release_lock; print ""; read -r "?按回车关闭窗口…"; exit "$result"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
if /usr/bin/pgrep -f '/Contents/MacOS/(Codex|ChatGPT)( |$)' >/dev/null; then
  print "请按 Command-Q 完全退出 Codex / ChatGPT 后再运行。"
  exit 1
else
  probe_result=$?
  (( probe_result == 1 )) || { print "无法查询应用进程，停止。"; exit 1; }
fi
[[ -f ./latest-backup.txt ]] || { print "找不到备份记录。"; exit 1; }
backup_dir=$(<./latest-backup.txt)
[[ -d "$backup_dir" && -f "$backup_dir/source-path.txt" ]] || { print "备份记录无效。"; exit 1; }
source_app=$(<"$backup_dir/source-path.txt")
[[ "$source_app" == /* && ! -L "$source_app" ]] || { print "恢复目标路径无效。"; exit 1; }
if (( EUID != 0 )) && { [[ -f "$backup_dir/admin-required" ]] || [[ ! -w "$source_app" || ! -w "${source_app:h}" ]]; }; then
  elevate_for_install
fi
backup_app="$backup_dir/${source_app:t}"
[[ -d "$source_app" && -d "$backup_app" ]] || { print "应用或备份已移动，请按说明手动恢复。"; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$source_app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$source_app/Contents/Info.plist")
[[ "$version/$build" == "$(<"$backup_dir/version.txt")" ]] || { print "应用已升级，不自动用旧备份覆盖新版本。"; exit 1; }
acquire_lock "$source_app"
[[ -f "$backup_dir/patched.manifest.json" ]] || { print "本次修复未完整完成，请按说明手动恢复；不会自动覆盖安装。"; exit 1; }
/usr/bin/perl ./verify-tree.pl --verify "$source_app" "$backup_dir/patched.manifest.json"
restore_application "$source_app" "$backup_app"
print "原应用文件及原签名已从备份恢复。语言配置如需恢复，请运行第 4 个入口。"
