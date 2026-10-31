#!/bin/sh
# 离线测试：升级安装时把旧 config.sh 迁移为 config.ini
set -u
REPO="$1"
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

# 从 customize.sh 抽出迁移段做隔离测试（不执行整装脚本）
sed -n '/旧版只有 config.sh/,/^    fi$/p' "$REPO/customize.sh" > "$TMP/migrate.sh"
chk "迁移段已提取" "$([ -s "$TMP/migrate.sh" ] && echo yes || echo no)" "yes"

INSTALLED="$TMP/installed"
MODPATH="$TMP/new"
mkdir -p "$INSTALLED/config" "$MODPATH/config"
ui_print() { echo "ui: $*"; }
COPIED_CONFIG=0

# 场景 1：旧版只有 config.sh
cat > "$INSTALLED/config/config.sh" <<"EOF"
# 旧配置
auto_load=1
replace_rules=1
manager_name=旧梦一场雨
touch /tmp/MIGRATE_SHOULD_NOT_RUN
EOF
printf "auto_load=1\n" > "$MODPATH/config/config.ini"
rm -f /tmp/MIGRATE_SHOULD_NOT_RUN
. "$TMP/migrate.sh" >/dev/null 2>&1
chk "迁移后含旧值" "$(grep -c "^manager_name=旧梦一场雨$" "$MODPATH/config/config.ini")" "1"
chk "迁移后注释保留" "$(grep -c "^# 旧配置$" "$MODPATH/config/config.ini")" "1"
chk "非 KV 行被丢弃" "$(grep -c "touch /tmp" "$MODPATH/config/config.ini" || true)" "0"
chk "旧文件备份为 .bak" "$([ -f "$MODPATH/config/config.sh.bak" ] && echo yes || echo no)" "yes"
chk "恶意命令未执行" "$([ -f /tmp/MIGRATE_SHOULD_NOT_RUN ] && echo ran || echo safe)" "safe"
chk "COPIED_CONFIG 置位" "$COPIED_CONFIG" "1"

# 场景 2：已有 config.ini 时不迁移（以新格式为准）
rm -rf "$INSTALLED" "$MODPATH"; mkdir -p "$INSTALLED/config" "$MODPATH/config"
printf "auto_load=0\n" > "$INSTALLED/config/config.ini"
printf "auto_load=1\nreplace_rules=2\n" > "$INSTALLED/config/config.sh"
printf "auto_load=1\n" > "$MODPATH/config/config.ini"
. "$TMP/migrate.sh" >/dev/null 2>&1
chk "已有 config.ini 时不覆盖" "$(cat "$MODPATH/config/config.ini")" "auto_load=1"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
