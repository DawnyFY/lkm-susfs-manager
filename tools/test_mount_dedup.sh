#!/bin/sh
# 离线测试：sus_mount / try_umount 按「本次开机」去重
set -u
REPO="$1"
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

MODDIR="$TMP"; mkdir -p "$TMP/config" "$TMP/state"
# 假 BIN：把调用追加到 calls 文件，支持 add_sus_mount / add_try_umount
cat > "$TMP/bin" <<"EOF"
#!/bin/sh
case "$1" in
  add_sus_mount)   echo "sm $2" >> "$CALLS" ;;
  add_try_umount)  echo "tu $2" >> "$CALLS" ;;
esac
exit 0
EOF
chmod 755 "$TMP/bin"
BIN="$TMP/bin"; export CALLS="$TMP/calls"; : > "$CALLS"
. "$REPO/common.sh"

sus_mount_add_once /data/adb/modules/a; chk "首次添加成功" "$?" "0"
sus_mount_add_once /data/adb/modules/a; chk "重复添加被跳过" "$?" "2"
chk "内核只被调用一次" "$(grep -c "sm /data/adb/modules/a" "$CALLS")" "1"

try_umount_add_once /apex/x;  chk "try_umount 首次成功" "$?" "0"
try_umount_add_once /apex/x;  chk "try_umount 重复跳过" "$?" "2"
chk "try_umount 只调用一次" "$(grep -c "tu /apex/x" "$CALLS")" "1"

# boot_id 变化：记录失效，可重新添加
printf "different-boot\n" > "$STATE/sus_mount_added.txt.boot"
sus_mount_add_once /data/adb/modules/a; chk "新 boot 重新添加" "$?" "0"
chk "新 boot 后总调用 2 次" "$(grep -c "sm /data/adb/modules/a" "$CALLS")" "2"

# 失败不记账：下次仍会重试
cat > "$TMP/bin2" <<"EOF"
#!/bin/sh
exit 1
EOF
chmod 755 "$TMP/bin2"
BIN="$TMP/bin2"
sus_mount_add_once /data/adb/modules/b; chk "失败返回 1" "$?" "1"
chk "失败未记账" "$(grep -c "/data/adb/modules/b" "$STATE/sus_mount_added.txt" || true)" "0"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"