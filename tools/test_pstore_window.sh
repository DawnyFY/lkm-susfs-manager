#!/bin/sh
# 回归：崩溃现场窗口必须能跨过"panic 之后还有大量打印"（audit R2-2）
# 旧实现只看尾部 512 KB，触发行被 700 KB 打印挤出窗口 → 崩溃循环保护失效。
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi

TMP=$(mktemp -d)
MOD="$TMP/mod"
mkdir -p "$MOD/state" "$MOD/config"
P="$TMP/pstore"
mkdir -p "$P"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

SUSFS_TEST_HOOK=1 PSTORE_DIR="$P" MODDIR="$MOD" . "$REPO/common.sh" >/dev/null 2>&1

NL=$(printf '\nx')
FILLER=$(printf 'x%.0s' $(seq 1 120) 2>/dev/null || printf 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')

# A) 本模块崩溃 + 其后 ~700 KB 打印
{
    echo "[  50.0] Unable to handle kernel paging request"
    echo "[  50.0] Modules linked in: susfs_guard_lkm(O) zram"
    echo "[  50.0] pc : susfs_guard_lkm+0x2a10/0x4000 [susfs_guard_lkm]"
    echo "[  50.0] Call trace:"
    echo "[  50.0]  susfs_guard_lkm+0x2a10/0x4000 [susfs_guard_lkm]"
    i=0; while [ $i -lt 6000 ]; do echo "[  60.0] tail print $i $FILLER"; i=$((i+1)); done
} > "$P/console-ramoops-0"

chk "崩溃在 700KB 之前仍能判定为自己" "$(pstore_crash_suspect && echo suspect || echo clear)" "suspect"

# B) 别人的崩溃 + 其后 ~700 KB 打印
rm -f "$P"/*
{
    echo "[  50.0] Unable to handle kernel NULL pointer dereference"
    echo "[  50.0] Modules linked in: susfs_guard_lkm(O) zram"
    echo "[  50.0] pc : stat_readable_show+0xb4/0x67c [zram]"
    echo "[  50.0] Call trace:"
    echo "[  50.0]  stat_readable_show+0xb4/0x67c [zram]"
    i=0; while [ $i -lt 6000 ]; do echo "[  60.0] tail print $i $FILLER"; i=$((i+1)); done
} > "$P/console-ramoops-0"

chk "别人的崩溃同样能跨窗口识别" "$(pstore_crash_suspect && echo suspect || echo clear)" "clear"
chk "能取出出错函数" "$(pstore_crash_foreign)" "stat_readable_show"

# C) 干净的开机日志（Qualcomm 设备常见）→ 不是 unknown，回落到 none（audit N1）
rm -f "$P"/*
{ i=0; while [ $i -lt 200 ]; do echo "[  10.0] normal boot log $i"; i=$((i+1)); done; } > "$P/console-ramoops-0"
chk "干净日志不算 unknown" "$(pstore_crash_unknown && echo yes || echo no)" "no"
chk "干净日志不算自己" "$(pstore_crash_suspect && echo suspect || echo clear)" "clear"
chk "干净日志不算外部" "$(pstore_crash_foreign)" ""

# D) 转储读不到（权限/半写）→ unknown；root 下读得到则跳过这条
rm -f "$P"/*
echo "[  10.0] unreadable dump" > "$P/console-ramoops-0"
chmod 000 "$P/console-ramoops-0" 2>/dev/null || true
if [ -r "$P/console-ramoops-0" ]; then
    echo "SKIP  读不到转储 → unknown（当前用户可读，跳过）"
else
    chk "读不到转储 → unknown" "$(pstore_crash_unknown && echo yes || echo no)" "yes"
fi
chmod 644 "$P/console-ramoops-0" 2>/dev/null || true

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
