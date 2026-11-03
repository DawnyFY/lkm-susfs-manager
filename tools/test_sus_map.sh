#!/bin/sh
# 离线测试：sus_map 写入 /proc/susfs_map 与归属撤销
set -u
REPO="$1"
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

MODDIR="$TMP"; mkdir -p "$TMP/config" "$TMP/state"
export SUS_MAP_NODE="$TMP/sus_map"
: > "$SUS_MAP_NODE"
. "$REPO/common.sh"

chk "节点存在判为支持" "$(sus_map_supported && echo yes || echo no)" "yes"

sus_map_add /data/adb/modules/x/lib.so; chk "add 返回成功" "$?" "0"
chk "add 写入格式" "$(cat "$SUS_MAP_NODE")" "add /data/adb/modules/x/lib.so"

sus_map_del /data/adb/modules/x/lib.so; chk "del 返回成功" "$?" "0"
chk "del 写入格式" "$(tail -1 "$SUS_MAP_NODE")" "del /data/adb/modules/x/lib.so"

chk "空路径被拒" "$(sus_map_add "" && echo ok || echo rejected)" "rejected"

record_own_sus_map /data/adb/modules/x/lib.so
record_own_sus_map /data/adb/modules/x/lib.so
chk "归属清单去重" "$(grep -c "lib.so" "$TMP/state/sus_map_added.txt")" "1"

clear_own_sus_map >/dev/null 2>&1
chk "撤销写入 del" "$(tail -1 "$SUS_MAP_NODE")" "del /data/adb/modules/x/lib.so"
chk "撤销后清单清空" "$(wc -l < "$TMP/state/sus_map_added.txt")" "0"

rm -f "$SUS_MAP_NODE"
chk "节点缺失判为不支持" "$(sus_map_supported && echo yes || echo no)" "no"
sus_map_add /x; chk "节点缺失时 add 失败" "$?" "1"

chk "apply 有 sus_map 段" "$(grep -c "6b. sus_map" "$REPO/apply.sh")" "1"
chk "replace_rules=1 撤销 sus_map" "$(grep -c "clear_own_sus_map" "$REPO/apply.sh")" "1"
chk "ctl set_file 白名单含 sus_map" "$(sed -n '/    set_file)/,/;;/p' "$REPO/ctl.sh" | grep -c "sus_map" )" "1"
chk "ctl get_file 白名单含 sus_map" "$(sed -n '/    get_file)/,/;;/p' "$REPO/ctl.sh" | grep -c "sus_map")" "1"
chk "bundle 7 段" "$(grep -c "_names=\"config.ini.*sus_map.txt\"" "$REPO/ctl.sh")" "1"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"