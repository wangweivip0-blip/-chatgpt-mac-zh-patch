#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}"
result=0
trap 'result=$?; print ""; read -r "?按回车关闭窗口…"; exit "$result"' EXIT
/usr/bin/perl ./locale-tool.pl --restore
