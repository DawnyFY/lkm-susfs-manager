#!/bin/sh
# 回归：老代码审查的 MAJOR 项（audit-legacy）
#  M1  probe_cache 必须能真正命中（写入要带换行）
#  M1b 缓存签名必须包含 LKM 装载状态
#  M3  status 必须有 anonymous_stats 字段（第 50 个，追加在末尾）
#  M4  apply_result 跨 boot 要报 stale
#  M2  reset_defaults 必须先备份、逐项检查
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi
C="$REPO/ctl.sh"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

# M1：写缓存那一行必须带换行
chk "M1 缓存写入带换行" "$(grep -c "printf 'ok=1\\\\n'" "$C")" "1"
chk "M1 旧写法已消失" "$(grep -c "^        printf 'ok=1'\$" "$C")" "0"

# M1b：签名含 LKM 状态
chk "M1b 签名含 LKM" "$(grep -c '_sig_lkm=1' "$C")" "1"
chk "M1b 签名格式三字段" "$(grep -c "printf '%s|%s|%s' \"\$_sig_bid\"" "$C")" "1"

# M3：status 输出该字段
chk "M3 status 有 anonymous_stats" "$(grep -c "printf 'anonymous_stats=%s" "$C")" "2"
B="$ROOT/tools/fixtures/status.baseline"
chk "M3 基线已含该键" "$(grep -cx "anonymous_stats" "$B")" "1"

# M4：跨 boot 判 stale
chk "M4 stale 分支存在" "$(grep -c 'apply_result=stale' "$C")" "1"
chk "M4 读 apply_result_boot" "$(grep -c '_ARB < "\$STATE/apply_result_boot"' "$C")" "1"

# M2：备份 + 逐项检查
chk "M2 先建备份目录" "$(grep -c 'mkdir -p "$_rd_bak"' "$C")" "1"
chk "M2 写入检查函数" "$(grep -c '_rd_write()' "$C")" "1"
chk "M2 失败时报 failed" "$(grep -c 'echo "failed: ' "$C")" "2"

# 附带：uninstall.sh 存在且可执行入库
chk "uninstall.sh 存在" "$([ -f "$REPO/uninstall.sh" ] && echo yes || echo no)" "yes"
chk "uninstall.sh 在可执行清单" "$(grep -c '"uninstall.sh"' "$ROOT/tools/build_module_zip.py")" "1"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
