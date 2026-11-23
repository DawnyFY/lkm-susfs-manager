#!/bin/sh
# 回归：ctl.sh clear_log / clear_logs（WebUI 日志页「清理」）
# clear_log：轮转成 .1 并写一行分隔头；clear_logs：连备份一起删
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi

TMP=$(mktemp -d)
MOD="$TMP/mod"
mkdir -p "$MOD/state" "$MOD/config" "$MOD/lib"
sed "s#/data/adb/modules/susfs_allinone#$MOD#g" "$REPO/ctl.sh" > "$MOD/ctl.sh"
sed "s#/data/adb/modules/susfs_allinone#$MOD#g" "$REPO/common.sh" > "$MOD/common.sh"
printf '%s\n' "id=susfs_allinone" "version=1.3.0" "versionCode=22" > "$MOD/module.prop"
printf 'load line 1\nload line 2\n' > "$MOD/load.log"
printf 'apply line 1\napply line 2\n' > "$MOD/apply.log"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

out=$(MODDIR="$MOD" sh "$MOD/ctl.sh" clear_log 2>&1)
chk "clear_log 返回 cleared=2" "$(printf '%s' "$out" | grep -o 'cleared=[0-9]*')" "cleared=2"
chk "load.log 已轮转为 .1" "$([ -f "$MOD/load.log.1" ] && echo yes || echo no)" "yes"
chk "apply.log 已轮转为 .1" "$([ -f "$MOD/apply.log.1" ] && echo yes || echo no)" "yes"
chk ".1 里是旧内容" "$(grep -c 'load line 1' "$MOD/load.log.1")" "1"
chk "新 load.log 只有分隔头" "$(grep -c '已被清理' "$MOD/load.log")" "1"
chk "新 apply.log 只有分隔头" "$(grep -c '已被清理' "$MOD/apply.log")" "1"

out2=$(MODDIR="$MOD" sh "$MOD/ctl.sh" clear_logs 2>&1)
chk "clear_logs 返回 removed=4" "$(printf '%s' "$out2" | grep -o 'removed=[0-9]*')" "removed=4"
chk "clear_logs 后无残留" "$(ls "$MOD"/load.log* "$MOD"/apply.log* 2>/dev/null | wc -l)" "0"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
