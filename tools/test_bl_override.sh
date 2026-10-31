#!/bin/sh
# 离线测试：force_bl_unlocked 走独立标记文件，通用配置写入器无法绕过
set -u
REPO="$1"
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

MOD="$TMP/mod"; mkdir -p "$MOD/config" "$MOD/state"
# ctl.sh 已固定模块路径：复制时把真实路径替换成临时目录，保持行为一致
sed "s#/data/adb/modules/susfs_allinone#$MOD#g" "$REPO/ctl.sh" > "$MOD/ctl.sh"
sed "s#/data/adb/modules/susfs_allinone#$MOD#g" "$REPO/common.sh" > "$MOD/common.sh"
cp "$REPO/kmi.sh" "$MOD/kmi.sh"
printf "id=x\nversion=1.2.0\n" > "$MOD/module.prop"
MODDIR="$MOD"; CONFIG="$MOD/config"; STATE="$MOD/state"
. "$MOD/common.sh"

# 默认未解锁
printf "auto_load=1\n" > "$CONFIG/config.ini"
bl_unlocked; chk "默认未解锁" "$?" "1"

# set_flag 写独立文件，不进 config.ini
sh "$MOD/ctl.sh" set_flag force_bl_unlocked 1 >/dev/null 2>&1
chk "标记文件为 1" "$(cat "$STATE/force_bl_unlocked" 2>/dev/null)" "1"
chk "config.ini 不含该键" "$(grep -c "^force_bl_unlocked=" "$CONFIG/config.ini" 2>/dev/null || true)" "0"
bl_unlocked; chk "覆盖后视为已解锁" "$?" "0"

# 关闭
sh "$MOD/ctl.sh" set_flag force_bl_unlocked 0 >/dev/null 2>&1
chk "标记文件为 0" "$(cat "$STATE/force_bl_unlocked")" "0"

# 通用写入器写入该键必须被拒
bad=$(printf "%s" "force_bl_unlocked=1" | base64 | tr -d "\n")
chk "set_config 拒绝该键" "$(sh "$MOD/ctl.sh" set_config "$bad" 2>&1 | tail -1)" "rejected: line 1: reserved key force_bl_unlocked"

# 重复键被拒
dup=$(printf "auto_load=1\nauto_load=0" | base64 | tr -d "\n")
chk "拒绝重复键" "$(sh "$MOD/ctl.sh" set_config "$dup" 2>&1 | tail -1)" "rejected: line 2: duplicate key auto_load"

# 旧位置迁移：config.ini 里的旧值迁到 state 后删除
rm -f "$STATE/force_bl_unlocked"
printf "auto_load=1\nforce_bl_unlocked=1\n" > "$CONFIG/config.ini"
_v=$(cfg_force_bl)
chk "旧值迁移生效" "$_v" "1"
chk "迁移后 state 文件为 1" "$(cat "$STATE/force_bl_unlocked" 2>/dev/null)" "1"
chk "迁移后 config.ini 已删除旧键" "$(grep -c "^force_bl_unlocked=" "$CONFIG/config.ini" 2>/dev/null || true)" "0"

# 拒绝未知键/非法值
chk "拒绝未知键" "$(sh "$MOD/ctl.sh" set_flag evil 1 2>&1 | tail -1)" "unknown flag"
chk "拒绝非法值" "$(sh "$MOD/ctl.sh" set_flag force_bl_unlocked 2 2>&1 | tail -1)" "bad value"

# 无尾换行追加（set_auto 路径）
printf "auto_load=1" > "$CONFIG/config.ini"
sh "$MOD/ctl.sh" set_auto 1 >/dev/null 2>&1 || true
chk "set_auto 后 auto_load 独立成行" "$(grep -c "^auto_load=" "$CONFIG/config.ini")" "1"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"