#!/bin/sh
# 回归：config.ini 若是 CRLF / 带尾随 TAB / 行内注释，cfg_get 必须给出干净值
# 背景：_CFG_CR 曾被写成跨行字面量（$(printf '<换行>')），命令替换吃掉换行后
# 该变量恒为空 → CR 裁剪整条失效 → CRLF 配置里所有开关都被当成"不等于 1"。
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi

TMP=$(mktemp -d)
MOD="$TMP/mod"
mkdir -p "$MOD/config" "$MOD/state"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

# 1) CRLF + 尾随 TAB + 行内注释
printf 'auto_load=1\r\nhide_sus_mnts=0\r\navc_spoof=1\t\r\nfake_cmdline_value=androidboot.x=1 # note\r\n' > "$MOD/config/config.ini"
out=$(MODDIR="$MOD" sh -c '. "'"$REPO"'/common.sh" >/dev/null 2>&1
printf "%s|%s|%s|%s|%s\n" "${#_CFG_CR}" "$(cfg_get auto_load D)" "$(cfg_get hide_sus_mnts D)" "$(cfg_get avc_spoof D)" "$(cfg_get fake_cmdline_value D)"')
chk "CR 变量长度为 1" "$(printf '%s' "$out" | cut -d'|' -f1)" "1"
chk "CRLF 的 auto_load" "$(printf '%s' "$out" | cut -d'|' -f2)" "1"
chk "CRLF 的 hide_sus_mnts" "$(printf '%s' "$out" | cut -d'|' -f3)" "0"
chk "TAB+CR 的 avc_spoof" "$(printf '%s' "$out" | cut -d'|' -f4)" "1"
chk "行内注释被去掉" "$(printf '%s' "$out" | cut -d'|' -f5)" "androidboot.x=1"

# 2) 重复键取最后一个（与 WebUI 一致）
printf 'replace_rules=0\nreplace_rules=2\n' > "$MOD/config/config.ini"
chk "重复键取最后" "$(MODDIR="$MOD" sh -c '. "'"$REPO"'/common.sh" >/dev/null 2>&1; cfg_get replace_rules D')" "2"

# 3) 缺键用默认值
chk "缺键给默认" "$(MODDIR="$MOD" sh -c '. "'"$REPO"'/common.sh" >/dev/null 2>&1; cfg_get not_exist DEF')" "DEF"

# 4) 文件不存在也给默认
rm -f "$MOD/config/config.ini"
chk "无配置给默认" "$(MODDIR="$MOD" sh -c '. "'"$REPO"'/common.sh" >/dev/null 2>&1; cfg_get any D2')" "D2"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
