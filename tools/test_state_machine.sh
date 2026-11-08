#!/bin/sh
# 离线测试：boot-completed 状态传递（rc=0/5 写 boot_stage_completed 并清守卫；rc=3 不写不清）
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }
build() {
    M="$1"; mkdir -p "$M/state"
    printf "description=test\n" > "$M/module.prop"
    cat > "$M/common.sh" <<'STUB'
boot_gate_ok() { return 0; }
_cf_gate() { return 0; }
cfg_ensure() { :; }
cfg_load() { :; }
clear_boot_guard() { rm -f "$STATE/boot_guard"; }
STUB
    printf "#!/system/bin/sh\nexit \${TEST_RC}\n" > "$M/apply.sh"
    sed "s#/data/adb/modules/susfs_allinone#$M#g" "$REPO/boot-completed.sh" > "$M/boot_under_test.sh"
}
run() { ( M="$1"; TEST_RC="$2"; STATE="$M/state"; export TEST_RC; sh "$M/boot_under_test.sh" >/dev/null 2>&1; echo $? ); }

M="$TMP/b0"; build "$M"; : > "$M/state/boot_guard"
rc=$(run "$M" 0)
chk "rc=0 退出 0" "$rc" "0"
chk "rc=0 清除 boot_guard" "$([ -f "$M/state/boot_guard" ] && echo yes || echo no)" "no"
chk "rc=0 写 boot_stage_completed" "$([ -s "$M/state/boot_stage_completed" ] && echo yes || echo no)" "yes"

M="$TMP/b5"; build "$M"; : > "$M/state/boot_guard"
rc=$(run "$M" 5)
chk "rc=5 退出 5" "$rc" "5"
chk "rc=5 清除 boot_guard" "$([ -f "$M/state/boot_guard" ] && echo yes || echo no)" "no"
chk "rc=5 写 boot_stage_completed" "$([ -s "$M/state/boot_stage_completed" ] && echo yes || echo no)" "yes"

M="$TMP/b3"; build "$M"; : > "$M/state/boot_guard"
rc=$(run "$M" 3)
chk "rc=3 退出 3" "$rc" "3"
chk "rc=3 保留 boot_guard" "$([ -f "$M/state/boot_guard" ] && echo yes || echo no)" "yes"
chk "rc=3 不写 boot_stage_completed" "$([ -e "$M/state/boot_stage_completed" ] && echo yes || echo no)" "no"

rm -rf "$TMP"
exit "$fail"
