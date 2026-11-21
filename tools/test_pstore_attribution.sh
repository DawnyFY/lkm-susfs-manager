#!/bin/sh
# 离线回归：pstore 崩溃归属判定
# 现场（vivo V2452A，1.2.9）：panic 栈在 zram 的 stat_readable_show，
# 但转储里含模块自己的加载日志 → 旧实现把这次崩溃认领成本模块的，暂停了自动加载。
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi

TMP=$(mktemp -d)
MOD="$TMP/mod"
mkdir -p "$MOD/state" "$MOD/config"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

PSTORE="$TMP/pstore"
mkdir -p "$PSTORE"
PS_DIR="$PSTORE"

# 让 common.sh 里的 _pstore_dir 指向临时目录
SUSFS_TEST_HOOK=1 PSTORE_DIR="$PS_DIR" MODDIR="$MOD" . "$REPO/common.sh" >/dev/null 2>&1

# 造一份「别人的崩溃」：模块加载日志 + Modules linked in 有本模块，但调用栈是 zram
cat > "$PS_DIR/console-ramoops-0" <<'DUMP'
[  109.250000] susfs_guard_lkm: init v2.3.0-gki ok
[  109.260000] susfs_guard_lkm: hooks installed, supercall taken over
[  127.990000] zram: Cannot change disksize for initialized device
[  142.060000] Unable to handle kernel NULL pointer dereference at virtual address 0000000000000028
[  142.060000] Internal error: Oops: 0000000096000005 [#1] PREEMPT SMP
[  142.060000] Modules linked in: susfs_guard_lkm(O) zram zsmalloc
[  142.060000] CPU: 3 PID: 9108 Comm: scene-daemon
[  142.060000] pc : stat_readable_show+0xb4/0x67c [zram]
[  142.060000] lr : stat_readable_show+0x68/0x67c [zram]
[  142.060000] Call trace:
[  142.060000]  stat_readable_show+0xb4/0x67c [zram]
[  142.060000]  dev_attr_show+0x20/0x50
[  142.060000]  sysfs_kf_seq_show+0x8c/0x120
DUMP

chk "别人的崩溃不算本模块" "$(pstore_crash_suspect && echo suspect || echo clear)" "clear"
chk "能取出出错函数" "$(pstore_fault_culprit "$PS_DIR/console-ramoops-0")" "stat_readable_show"
chk "外部崩溃可报告" "$([ -n "$(pstore_crash_foreign)" ] && echo yes || echo no)" "yes"

# 造一份「本模块的崩溃」：调用栈里真的有 susfs_guard_lkm
cat > "$PS_DIR/console-ramoops-1" <<'DUMP'
[   50.000000] Unable to handle kernel paging request at virtual address dead000000000000
[   50.000000] Modules linked in: susfs_guard_lkm(O) zram
[   50.000000] pc : susfs_guard_lkm+0x2a10/0x4000 [susfs_guard_lkm]
[   50.000000] Call trace:
[   50.000000]  susfs_guard_lkm+0x2a10/0x4000 [susfs_guard_lkm]
[   50.000000]  do_sys_openat2+0x98/0x120
DUMP

chk "栈里有本模块才算崩溃" "$(pstore_crash_suspect && echo suspect || echo clear)" "suspect"
chk "本模块崩溃不算外部" "$([ -z "$(pstore_crash_foreign)" ] && echo empty || echo has)" "empty"

# ack 之后不再报
FP=$(_pstore_fingerprint 2>/dev/null)
printf '%s\n' "$FP" > "$MOD/state/crash_ack"
chk "ack 之后不再判定" "$(pstore_crash_suspect && echo suspect || echo clear)" "clear"

# 干净设备：没有任何转储
rm -f "$PS_DIR"/*
chk "无转储时不判定" "$(pstore_crash_suspect && echo suspect || echo clear)" "clear"
chk "无转储时无外部崩溃" "$(pstore_crash_foreign)" ""

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
