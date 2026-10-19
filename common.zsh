# 由入口脚本加载；不直接执行。
CODEX_ZH_TOOL_DIR="${${(%):-%x}:A:h}"
CODEX_ZH_LOCK=""
acquire_lock() {
  local requested="${1}.zh-repair.lock"
  /bin/mkdir -m 700 "$requested" 2>/dev/null || { print "安装位置已被其他修复/恢复操作锁定，或无写权限：$requested"; return 1; }
  CODEX_ZH_LOCK="$requested"
}
release_lock() {
  if [[ -n "$CODEX_ZH_LOCK" ]]; then
    /bin/rmdir "$CODEX_ZH_LOCK" || print "未能移除本次操作锁：$CODEX_ZH_LOCK"
    CODEX_ZH_LOCK=""
  fi
}
restore_application() {
  local target="$1" original="$2"
  local manifest="${original}.manifest.json"
  local work="${target:h}/.chatgpt-zh-restore-$$.noindex"
  /bin/mkdir -m 700 "$work" || return 1
  local stage="$work/${target:t}" displaced="$work/modified-before-restore.bundle"
  [[ ! -e "$stage" && ! -e "$displaced" ]] || return 1
  /usr/bin/perl "$CODEX_ZH_TOOL_DIR/verify-tree.pl" --verify "$original" "$manifest" || return 1
  /usr/bin/ditto "$original" "$stage" || return 1
  /usr/bin/perl "$CODEX_ZH_TOOL_DIR/verify-tree.pl" --verify "$stage" "$manifest" || return 1
  /bin/mv "$target" "$displaced" || return 1
  if ! /bin/mv "$stage" "$target"; then
    /bin/mv "$displaced" "$target" || print "切换失败，请从备份手动恢复到：$target"
    return 1
  fi
  local archive_dir="${original:h}/恢复前文件-$$.noindex"
  if /bin/mv "$work" "$archive_dir"; then
    print "已恢复原应用。替换前的文件保存在工具备份目录：$archive_dir"
  else
    print "已恢复原应用；替换前的文件暂存于隐藏目录：$work"
  fi
}

# 只在安装目录需要权限时由本机 sudo 授权；密码由 sudo 读取。
elevate_for_install() {
  (( EUID != 0 )) || { print "管理员权限下仍无法写入安装位置，停止。"; return 1; }
  [[ -n "${CODEX_ZH_ENTRY_SCRIPT:-}" && -f "$CODEX_ZH_ENTRY_SCRIPT" ]] || { print "入口脚本路径无效，停止授权。"; return 1; }
  print "此安装位置需要管理员权限。接下来由 macOS sudo 请求本机密码。"
  print "密码输入时终端不会显示字符；密码不会写入文件或发送。"
  local elevated_result=0
  /usr/bin/sudo /usr/bin/env \
    "HOME=$HOME" \
    "CODEX_ZH_LOGGING=${CODEX_ZH_LOGGING:-0}" \
    "CODEX_HOME=${CODEX_HOME:-$HOME/.codex}" \
    "CODEX_ZH_ORIGINAL_UID=$UID" \
    "CODEX_ZH_ORIGINAL_GID=$GID" \
    "CODEX_ZH_ORIGINAL_HOME=$HOME" \
    "CODEX_ZH_ORIGINAL_CONFIG=${CODEX_HOME:-$HOME/.codex}" \
    /bin/zsh "$CODEX_ZH_ENTRY_SCRIPT" "$@" || elevated_result=$?
  if (( elevated_result != 0 )); then
    print "管理员执行失败（退出码 $elevated_result），修复未完成。请查看上方报错。"
    return "$elevated_result"
  fi
  trap - EXIT
  exit 0
}
run_user_config() {
  if (( EUID == 0 )); then
    [[ "${CODEX_ZH_ORIGINAL_UID:-}" == <-> && "${CODEX_ZH_ORIGINAL_UID}" != 0 && -n "${CODEX_ZH_ORIGINAL_HOME:-}" && -n "${CODEX_ZH_ORIGINAL_CONFIG:-}" ]] || { print "缺少原用户信息，拒绝以 root 写入语言配置。"; return 1; }
    /usr/bin/sudo -u "#${CODEX_ZH_ORIGINAL_UID}" /usr/bin/env \
      "HOME=$CODEX_ZH_ORIGINAL_HOME" "CODEX_HOME=$CODEX_ZH_ORIGINAL_CONFIG" \
      /usr/bin/perl "$CODEX_ZH_TOOL_DIR/locale-tool.pl" "$@"
  else
    /usr/bin/perl "$CODEX_ZH_TOOL_DIR/locale-tool.pl" "$@"
  fi
}
