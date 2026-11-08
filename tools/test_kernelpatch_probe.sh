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
rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
