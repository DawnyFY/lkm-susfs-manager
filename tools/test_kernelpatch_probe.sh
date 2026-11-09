#!/bin/sh
# offline test: KernelPatch runtime probe
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }
. "$REPO/common.sh"

printf 'KP KernelPatch Version: d09\n' > "$TMP/kp.log"
chk "banner state=1" "$(SUSFS_TEST_HOOK=1 KERNELPATCH_DMESG_FILE="$TMP/kp.log" kernelpatch_kernel_state)" "1"
chk "banner version" "$(SUSFS_TEST_HOOK=1 KERNELPATCH_DMESG_FILE="$TMP/kp.log" kernelpatch_kernel_version)" "d09"
printf 'normal boot log without marker\n' > "$TMP/no.log"
chk "no banner state=0" "$(SUSFS_TEST_HOOK=1 KERNELPATCH_DMESG_FILE="$TMP/no.log" kernelpatch_kernel_state)" "0"
chk "missing dmesg=unknown" "$(SUSFS_TEST_HOOK=1 KERNELPATCH_DMESG_FILE="$TMP/missing.log" kernelpatch_kernel_state)" "unknown"
# 跨进程缓存：第一次读 dmesg，第二次（同 boot）应命中 state/kp_probe
M="$TMP/cache"; mkdir -p "$M/state" "$TMP/bin"
cat > "$TMP/bin/dmesg" <<'EOF'
#!/bin/sh
echo x >> "$DMESG_COUNT"
printf 'KernelPatch Version: d09\n'
EOF
chmod +x "$TMP/bin/dmesg"
printf 'test-boot\n' > "$TMP/bid"
: > "$TMP/count"
run_cached() { ( MODDIR="$M"; STATE="$M/state"; PROC_BOOT_ID_FILE="$TMP/bid"; PATH="$TMP/bin:$PATH"; export DMESG_COUNT="$TMP/count"; . "$REPO/common.sh"; kernelpatch_kernel_state; kernelpatch_kernel_version ); }
out1=$(run_cached); out2=$(run_cached)
chk "缓存：state=1" "$(printf '%s\n' "$out1" | sed -n '1p')" "1"
chk "缓存：version=d09" "$(printf '%s\n' "$out1" | sed -n '2p')" "d09"
chk "缓存：两次状态读取只调用一次 dmesg" "$(wc -l < "$TMP/count" | tr -d ' ')" "1"
chk "缓存：第二次仍返回版本" "$(printf '%s\n' "$out2" | sed -n '2p')" "d09"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
