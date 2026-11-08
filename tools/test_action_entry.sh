#!/bin/sh
# 离线测试：action.sh 的成败判定
# apply 失败时不能报成功，也不能清启动守卫（审计高危 #1 的回归用例）
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }
has() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }

M="$TMP/mod"; mkdir -p "$M"
cat > "$M/common.sh" <<'EOF'
ksu_branch() { echo "TEST"; }
select_susfs_bin() { return 0; }
susfs_kernel_ready() { [ "${TEST_READY:-0}" = "1" ]; }
susfs_kernel_kind() { echo "lkm"; }
clear_boot_guard() { [ -n "${TEST_GUARD:-}" ] && printf "cleared\n" >> "$TEST_GUARD"; }
EOF
# 只替换 MODDIR 一行，其余逻辑与线上 action.sh 完全一致
sed "s#MODDIR=/data/adb/modules/susfs_allinone#MODDIR=$M#" "$REPO/action.sh" > "$M/action_under_test.sh"

run_case() {
    # $1=load_rc $2=apply_rc $3=ready
    printf "#!/system/bin/sh\nexit %s\n" "$1" > "$M/load.sh"
    printf "#!/system/bin/sh\nexit %s\n" "$2" > "$M/apply.sh"
    rm -f "$M/guard"
    TEST_READY="$3" TEST_GUARD="$M/guard" sh "$M/action_under_test.sh" 2>&1
}

# A. 全部成功 → 报 OK 并清守卫
out=$(run_case 0 0 1)
chk "成功时打印 OK" "$(has "$out" "[OK] SUSFS 已就绪")" "yes"
chk "成功时清守卫" "$([ -f "$M/guard" ] && echo yes || echo no)" "yes"

# B. apply 失败（LKM 已就绪）→ 不能报 OK、不能清守卫
out=$(run_case 0 1 1)
chk "apply 失败时不报 OK" "$(has "$out" "[OK]")" "no"
chk "apply 失败时有失败提示" "$(has "$out" "应用未完成")" "yes"
chk "apply 失败时不清守卫" "$([ -f "$M/guard" ] && echo yes || echo no)" "no"

# C. load 未匹配内核(rc=2) + apply 失败 → 失败提示里带两个 rc
out=$(run_case 2 1 1)
chk "失败提示带 load rc" "$(has "$out" "load rc=2")" "yes"
chk "load rc=2 时不清守卫" "$([ -f "$M/guard" ] && echo yes || echo no)" "no"

# D. apply 成功但内核侧不就绪 → 仍然算失败
out=$(run_case 0 0 0)
chk "不就绪时不报 OK" "$(has "$out" "[OK]")" "no"
chk "不就绪时不清守卫" "$([ -f "$M/guard" ] && echo yes || echo no)" "no"

rm -rf "$TMP"
exit "$fail"
