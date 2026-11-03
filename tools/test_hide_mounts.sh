#!/bin/sh
# 离线测试：sus_mount.txt 优先写 /proc/susfs_hide_mounts，旧内核回退 add_sus_mount
set -u
REPO="$1"
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

MODDIR="$TMP"; mkdir -p "$TMP/config" "$TMP/state"
# 用普通文件模拟 proc 节点（真节点是命令接口，普通文件只验证写入内容）
export HIDE_MOUNTS_NODE="$TMP/hide_mounts"
: > "$HIDE_MOUNTS_NODE"
. "$REPO/common.sh"

chk "节点存在时判定支持" "$(hide_mounts_supported && echo yes || echo no)" "yes"

hide_mounts_add /data/adb/; chk "add 返回成功" "$?" "0"
chk "写入格式为 add <前缀>" "$(cat "$HIDE_MOUNTS_NODE")" "add /data/adb/"

hide_mounts_del /data/adb/; chk "del 返回成功" "$?" "0"
chk "del 写入格式" "$(tail -1 "$HIDE_MOUNTS_NODE")" "del /data/adb/"

# 归属记录 + 撤销（用非默认前缀，默认前缀不登记）
record_own_hide_mount /custom/prefix/
record_own_hide_mount /custom/prefix/   # 重复不重复记
chk "归属清单去重" "$(grep -c "^/custom/prefix/$" "$TMP/state/hide_mounts_added.txt")" "1"

# 上游默认前缀不能被登记（否则撤销会删掉它）
record_own_hide_mount /data/adb/
record_own_hide_mount /data/local/tmp/
chk "默认前缀不登记" "$(grep -cE "^/data/(adb|local/tmp)/$" "$TMP/state/hide_mounts_added.txt" || true)" "0"

clear_own_hide_mounts >/dev/null 2>&1
chk "撤销时写入 del" "$(tail -1 "$HIDE_MOUNTS_NODE")" "del /custom/prefix/"
chk "撤销后清单清空" "$(wc -l < "$TMP/state/hide_mounts_added.txt")" "0"

# 节点不存在 → 判定不支持，且不误写
rm -f "$HIDE_MOUNTS_NODE"
chk "节点缺失判为不支持" "$(hide_mounts_supported && echo yes || echo no)" "no"
hide_mounts_add /data/adb/; chk "节点缺失时 add 失败" "$?" "1"

# apply.sh 接线检查：第 6 节必须优先 hide_mounts，再回退 sus_mount_add_once
chk "apply 两处优先 hide_mounts（sus_mount + dex2oat）" "$(grep -c "if hide_mounts_add" "$REPO/apply.sh")" "2"
chk "apply 保留 add_sus_mount 回退" "$(grep -c "sus_mount_add_once" "$REPO/apply.sh")" "2"
chk "replace_rules=1 撤销 hide_mounts" "$(grep -c "clear_own_hide_mounts" "$REPO/apply.sh")" "1"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"