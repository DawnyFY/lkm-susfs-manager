#!/bin/sh
# 端到端测试：直接调用仓库里的 ctl.sh set_config，验证它真的会拦截
set -u
REPO="$1"
TMP=$(mktemp -d)
MOD="$TMP/mod"; mkdir -p "$MOD/config" "$MOD/state"
sed "s#/data/adb/modules/susfs_allinone#$MOD#g" "$REPO/ctl.sh" > "$MOD/ctl.sh"
sed "s#/data/adb/modules/susfs_allinone#$MOD#g" "$REPO/common.sh" > "$MOD/common.sh"
cp "$REPO/kmi.sh" "$MOD/kmi.sh" 2>/dev/null || true
printf "id=susfs_allinone\nversion=1.2.0\nversionCode=12\n" > "$MOD/module.prop"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

run_cfg() {
    _b64=$(printf "%s" "$1" | base64 | tr -d "\n")
    MODDIR="$MOD" sh "$MOD/ctl.sh" set_config "$_b64" 2>&1 | tail -1
}

ok=$(printf "# 注释\nauto_load=1\nfake_cmdline_value=androidboot.selinux=permissive\n")
chk "正常配置保存成功" "$(run_cfg "$ok")" "saved"
chk "正常配置已落盘" "$(grep -c "^auto_load=1$" "$MOD/config/config.ini")" "1"

# 值内空白 / 命令 / 引号：source 时会被拆成"赋值 + 命令"
chk "拒绝值内命令（空格）" "$(run_cfg "$(printf "spoof_uname_version=ok touch /tmp/PWNED\n")")" "rejected: line 1: whitespace in value"
chk "拒绝行内多命令" "$(run_cfg "$(printf "auto_load=1 STATE=/tmp/x export STATE\n")")" "rejected: line 1: whitespace in value"
chk "拒绝值内引号" "$(run_cfg "$(printf "manager_name=x\x27;id;\x27\n")")" "rejected: line 1: quote or backslash in value"
chk "注入未执行" "$(ls "$TMP/PWNED" 2>/dev/null | wc -l | tr -d " ")" "0"

# shell 元字符
chk "拒绝 & 注入" "$(run_cfg "$(printf "fake_cmdline_value=x&touch %s/PWNED\n" "$TMP")")" "rejected: line 1: whitespace in value"
chk "拒绝重定向" "$(run_cfg "$(printf "manager_name=y>%s/REDIR\n" "$TMP")")" "rejected: line 1: shell metacharacter in value"
chk "拒绝管道" "$(run_cfg "$(printf "auto_load=1|id\n")")" "rejected: line 1: shell metacharacter in value"
chk "重定向未执行" "$(ls "$TMP/REDIR" 2>/dev/null | wc -l | tr -d " ")" "0"

# 结构与保留键
chk "拒绝非 KEY=VALUE 行" "$(run_cfg "$(printf "this is not a kv line\n")")" "rejected: line 1: not KEY=VALUE"
chk "拒绝 PATH 劫持" "$(run_cfg "$(printf "PATH=/data/local/tmp\n")")" "rejected: line 1: reserved key PATH"
chk "拒绝 MODDIR 覆盖" "$(run_cfg "$(printf "MODDIR=/data/local/tmp/evil\n")")" "rejected: line 1: reserved key MODDIR"
chk "拒绝 STATE 覆盖" "$(run_cfg "$(printf "STATE=/tmp/x\n")")" "rejected: line 1: reserved key STATE"
chk "拒绝 CONFIG 覆盖" "$(run_cfg "$(printf "CONFIG=/tmp/x\n")")" "rejected: line 1: reserved key CONFIG"

# 用户自定义键必须放行（WebUI 会保留未知键）
chk "放行用户自定义键" "$(run_cfg "$(printf "my_own_key=keepme\nauto_load=1\n")")" "saved"
chk "自定义键已落盘" "$(grep -c "^my_own_key=keepme$" "$MOD/config/config.ini")" "1"
chk "被拒绝后原配置未被破坏" "$(grep -c "^auto_load=1$" "$MOD/config/config.ini")" "1"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"