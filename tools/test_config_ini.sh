#!/bin/sh
# 离线测试：config.ini 迁移 / 解析 / 不执行内容
set -u
REPO="$1"
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

MOD="$TMP/mod"; mkdir -p "$MOD/config" "$MOD/state"
cp "$REPO/common.sh" "$MOD/common.sh"
MODDIR="$MOD"; CONFIG="$MOD/config"; STATE="$MOD/state"
. "$MOD/common.sh"

# 1) 迁移：只提取 KEY=VALUE，绝不执行旧文件里的命令
cat > "$CONFIG/config.sh" <<"EOF"
# 用户注释
auto_load=1
replace_rules=1
manager_name=旧梦一场雨
touch /tmp/SHOULD_NOT_RUN
echo "malicious"
EOF
rm -f "$CONFIG/config.ini" /tmp/SHOULD_NOT_RUN
cfg_migrate >/dev/null 2>&1
chk "迁移后 config.ini 存在" "$([ -f "$CONFIG/config.ini" ] && echo yes || echo no)" "yes"
chk "旧文件保留为 .bak" "$([ -f "$CONFIG/config.sh.bak" ] && echo yes || echo no)" "yes"
chk "恶意命令未执行" "$([ -f /tmp/SHOULD_NOT_RUN ] && echo ran || echo safe)" "safe"
chk "非 KEY=VALUE 行被丢弃" "$(grep -c "touch /tmp" "$CONFIG/config.ini" || true)" "0"
chk "注释保留" "$(grep -c "^# 用户注释" "$CONFIG/config.ini")" "1"

# 2) 解析：cfg_load 读出变量，不执行值
printf "auto_load=1\nreplace_rules=2\nmanager_name=测试名\nfake_cmdline_value=a=b=c\n" > "$CONFIG/config.ini"
cfg_load
chk "auto_load 读取" "$auto_load" "1"
chk "replace_rules 读取" "$replace_rules" "2"
chk "中文值读取" "$manager_name" "测试名"
chk "含等号的值读取" "$fake_cmdline_value" "a=b=c"

# 3) cfg_get 单键读取带默认值
chk "cfg_get 命中" "$(cfg_get auto_load)" "1"
chk "cfg_get 缺省" "$(cfg_get not_exist fallback)" "fallback"

# 4) 恶意值不会被当成命令（纯赋值）
rm -f /tmp/INI_SHOULD_NOT_RUN
cat > "$CONFIG/config.ini" <<"EOF"
manager_name=$(touch /tmp/INI_SHOULD_NOT_RUN)
EOF
cfg_load >/dev/null 2>&1
chk "命令替换字面量未执行" "$([ -f /tmp/INI_SHOULD_NOT_RUN ] && echo ran || echo safe)" "safe"
chk "值按字面量保留" "$manager_name" "$(printf '%s' '$(touch /tmp/INI_SHOULD_NOT_RUN)')"

# 5) cfg_ensure：缺失时从 default 恢复
rm -f "$CONFIG/config.ini"
printf "auto_load=0\n" > "$CONFIG/config.ini.default"
cfg_ensure
chk "从 default 恢复" "$(cat "$CONFIG/config.ini")" "auto_load=0"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"