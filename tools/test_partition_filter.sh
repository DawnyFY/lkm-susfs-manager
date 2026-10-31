#!/bin/sh
# 离线测试：真实分区过滤（auto_try_umount 的强制保护）
set -u
REPO="$1"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1  expect=[$3] got=[$2]"; fail=1; fi; }
MODDIR=$(mktemp -d); mkdir -p "$MODDIR/config" "$MODDIR/state"
. "$REPO/common.sh"
verdict() { if is_legit_partition_mount "$1" "$2"; then echo legit; else echo module; fi; }

chk "ext4 根分区" "$(verdict ext4 /)" "legit"
chk "erofs 根分区" "$(verdict erofs /)" "legit"
chk "f2fs 根分区" "$(verdict f2fs /)" "legit"
chk "ext4 子目录(模块 bind)" "$(verdict ext4 /system/app/Foo)" "module"
chk "overlay 根" "$(verdict overlay /)" "module"
chk "tmpfs 根" "$(verdict tmpfs /)" "module"
chk "f2fs 子路径" "$(verdict f2fs /adb/modules/x)" "module"

rm -rf "$STATE"
# 集成断言：apply.sh 必须无条件调用过滤函数
chk "apply 调用过滤" "$(grep -c 'is_legit_partition_mount "$_fs" "$_root" && continue' "$REPO/apply.sh")" "1"
chk "过滤无 skip_legit_mounts 门控" "$(grep -B1 'is_legit_partition_mount "$_fs"' "$REPO/apply.sh" | grep -c 'skip_legit_mounts' || true)" "0"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"