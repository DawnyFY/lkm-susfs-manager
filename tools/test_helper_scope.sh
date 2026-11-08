#!/bin/sh
# 离线测试：helper 内部变量不得覆盖调用方变量（审计高危 #2 的回归用例）
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }
M="$TMP/mod"; mkdir -p "$M/state" "$M/config"

out=$(
  MODDIR="$M"
  . "$REPO/common.sh"
  # 1) record_own_hide_mount 不能覆盖调用方的 _n（apply.sh 的计数循环）
  _n=0
  for _p in /system/a /system/b; do
      _n=$((_n + 1))
      record_own_hide_mount "$_p"
  done
  echo "loop_n=$_n"
  # 2) record_our_path 不能覆盖调用方的 _f（Scene 循环的路径变量）
  _f="sentinel-f"
  record_our_path "/x/y"
  echo "f_after=$_f"
  # 3) clear_own_hide_mounts / clear_own_paths 不能覆盖 _f/_n
  _f="sentinel-2"; _n=7
  clear_own_hide_mounts >/dev/null 2>&1
  clear_own_paths >/dev/null 2>&1
  echo "f_after_clear=$_f"
  echo "n_after_clear=$_n"
  # 4) is_detection_app_path 不能覆盖 _p
  _p="sentinel-p"
  is_detection_app_path "/nope" >/dev/null 2>&1
  echo "p_after=$_p"
)
chk "计数循环 _n 未被覆盖" "$(printf "%s\n" "$out" | sed -n "s/^loop_n=//p")" "2"
chk "record_our_path 不覆盖 _f" "$(printf "%s\n" "$out" | sed -n "s/^f_after=//p")" "sentinel-f"
chk "clear_* 不覆盖 _f" "$(printf "%s\n" "$out" | sed -n "s/^f_after_clear=//p")" "sentinel-2"
chk "clear_* 不覆盖 _n" "$(printf "%s\n" "$out" | sed -n "s/^n_after_clear=//p")" "7"
chk "is_detection_app_path 不覆盖 _p" "$(printf "%s\n" "$out" | sed -n "s/^p_after=//p")" "sentinel-p"

rm -rf "$TMP"
exit "$fail"
