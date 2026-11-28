#!/bin/sh
# 同步上游 ver2.3.0 后的配套：日志开关 + 资产/清单一致性
set -u
REPO="$1"
[ -f "$REPO/module/module.prop" ] && REPO="$REPO/module"
export REPO
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

chk "有 susfs_log_apply" "$(grep -c "^susfs_log_apply()" "$REPO/common.sh")" "1"
chk "apply 调用日志开关" "$(grep -c "susfs_log_apply" "$REPO/apply.sh")" "1"
chk "配置有 susfs_log" "$(grep -c "^susfs_log=" "$REPO/config/config.ini")" "1"
chk "默认关闭（0）" "$(grep "^susfs_log=" "$REPO/config/config.ini" | cut -d= -f2)" "0"
chk "cfg_load 认这个键" "$(grep -c "susfs_log) susfs_log=" "$REPO/common.sh")" "1"

chk ".ko 数量" "$(ls "$REPO"/lib/susfs_guard_lkm-*.ko 2>/dev/null | wc -l | tr -d " ")" "8"
chk "symbols 数量" "$(ls "$REPO"/lib/symbols/*.symbols 2>/dev/null | wc -l | tr -d " ")" "8"
low=0
for f in "$REPO"/lib/symbols/*.symbols; do
    n=$(grep -c . "$f")
    [ "$n" -lt 120 ] && low=$((low + 1))
done
chk "无过短的符号清单（新版应 >=120）" "$low" "0"
# MSYS 上 chmod 不落 exec 位，改为校验打包脚本把它列进 EXEC_NAMES（zip 里才是 755）
chk "loader 被 build 脚本设为可执行" "$(grep -c "bin/susfs_insmod" "$REPO/../tools/build_module_zip.py")" "1"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"