#!/bin/sh
# 离线测试：模块完整性清单（.cache.files）自检
set -u
REPO="$1"
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

MOD="$TMP/mod"; mkdir -p "$MOD/webroot" "$MOD/config" "$MOD/state"
printf "id=x\nversion=1.2.1\n" > "$MOD/module.prop"
printf "echo hi\n" > "$MOD/apply.sh"
printf "body{}\n" > "$MOD/webroot/style.css"

# 生成清单（与构建脚本同样的格式）
( cd "$MOD" && sha256sum apply.sh webroot/style.css > .cache.files )
printf "version=1.2.1\nmanifest_sha256=abc\n" > "$MOD/.cache.meta"

MODDIR="$MOD"; mkdir -p "$MOD/state"
. "$REPO/common.sh"

_cf; chk "未修改时校验通过" "$?" "0"
_cf_run; chk "_cf_run 返回 0" "$?" "0"
chk "状态文件为 ok" "$(cat "$MOD/state/.cache.idx")" "ok"


# 改 config/ 或 state/ 不应触发 modified（抗误报）
printf "auto_load=0\n" > "$MOD/config/config.ini"
printf "x\n" > "$MOD/state/some_state"
_cf; chk "改 config/state 不误报" "$?" "0"
# 篡改一个文件
printf "echo pwned\n" >> "$MOD/apply.sh"
_cf >/dev/null 2>&1; chk "修改后校验失败" "$?" "1"
_cf_run >/dev/null 2>&1; chk "_cf_run 返回 1" "$?" "1"
chk "状态文件为 modified" "$(cat "$MOD/state/.cache.idx")" "modified"
chk "_cf_state 读回 modified" "$(_cf_state)" "modified"

# 缺文件也算修改
rm -f "$MOD/webroot/style.css"
_cf >/dev/null 2>&1; chk "缺文件校验失败" "$?" "1"

# 无清单 -> unknown
rm -f "$MOD/.cache.files"
_cf; chk "无清单返回 2" "$?" "2"
_cf_run >/dev/null 2>&1; chk "无清单 check 返回 0" "$?" "0"
chk "无清单状态 unknown" "$(cat "$MOD/state/.cache.idx")" "unknown"

# .cache.meta 读取
chk "meta 版本" "$(grep -m1 '^version=' "$MOD/.cache.meta" | cut -d= -f2-)" "1.2.1"

# 接线检查

# 启动闸门：文件被改时 _cf_gate 必须返回 1，正常时 0
rm -f "$MOD/.cache.files"
( cd "$MOD" && sha256sum apply.sh > .cache.files )
printf "echo hi\n" > "$MOD/apply.sh"
( cd "$MOD" && sha256sum apply.sh > .cache.files )
_cf_gate; chk "闸门放行正常文件" "$?" "0"
printf "echo evil\n" >> "$MOD/apply.sh"
_cf_gate >/dev/null 2>&1; chk "闸门拦截被改文件" "$?" "1"

chk "post-fs-data 有闸门" "$(grep -c "_cf_gate" "$REPO/post-fs-data.sh")" "1"
chk "boot-completed 有闸门" "$(grep -c "_cf_gate" "$REPO/boot-completed.sh")" "1"
chk "load 有闸门" "$(grep -c "_cf_gate" "$REPO/load.sh")" "1"
chk "apply 拒绝执行" "$(grep -c "拒绝应用规则" "$REPO/apply.sh")" "1"
chk "apply.sh 调用 _cf_run" "$(grep -c "_cf_run" "$REPO/apply.sh")" "1"
chk "load.sh 调用 _cf_run" "$(grep -c "_cf_run" "$REPO/load.sh")" "1"
chk "ctl 触发校验并输出" "$(grep -c "_cf_run" "$REPO/ctl.sh")" "1"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"