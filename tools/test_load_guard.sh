#!/bin/sh
# 1.3.3 加载自愈守卫：连续失败自动 disable，成功清零
set -u
REPO="$1"
[ -f "$REPO/module/module.prop" ] && REPO="$REPO/module"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

chk "load.sh 调用守卫" "$(grep -c "^load_guard_begin || exit 0" "$REPO/load.sh")" "1"
chk "成功路径清零" "$(grep -c "^load_guard_ok$\|^    load_guard_ok$" "$REPO/load.sh")" "2"
chk "ctl.sh 有 enable" "$(grep -c "^    enable)$" "$REPO/ctl.sh")" "1"

T=$(mktemp -d)
mkdir -p "$T/state"
run() {
  MODDIR="$T" STATE="$T/state" load_retry_max="$1" sh -c '. "$0/common.sh" >/dev/null 2>&1; load_guard_begin' "$REPO"
}

# 第 1 次：应放行并写下计数 1
out=$(run 2 2>&1); rc=$?
chk "首次放行" "$rc" "0"
chk "计数写为 1" "$(cat "$T/state/load_attempts" 2>/dev/null)" "1"

# 第 2 次：仍放行，计数 2
out=$(run 2 2>&1); rc=$?
chk "第二次仍放行" "$rc" "0"
chk "计数写为 2" "$(cat "$T/state/load_attempts" 2>/dev/null)" "2"

# 第 3 次：超限，必须禁用并返回非 0
out=$(run 2 2>&1); rc=$?
chk "超限拒绝加载" "$rc" "1"
chk "写了 disable 标记" "$([ -f "$T/disable" ] && echo yes || echo no)" "yes"
chk "提示含 enable" "$(printf "%s" "$out" | grep -c "ctl.sh enable")" "1"

# 成功后清零：计数文件删除后应重新放行
rm -f "$T/disable"
MODDIR="$T" STATE="$T/state" sh -c '. "$0/common.sh" >/dev/null 2>&1; load_guard_ok' "$REPO"
chk "成功后清零" "$([ -f "$T/state/load_attempts" ] && echo 存在 || echo 已清)" "已清"
out=$(run 2 2>&1); rc=$?
chk "清零后可再次加载" "$rc" "0"

# 阈值 1：一次失败即禁用
rm -f "$T/state/load_attempts" "$T/disable"
run 1 >/dev/null 2>&1
out=$(run 1 2>&1); rc=$?
chk "阈值1时第二次禁用" "$rc" "1"

rm -rf "$T"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"