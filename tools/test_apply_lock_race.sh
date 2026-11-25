#!/bin/sh
# 并发接管的回归：多个进程同时抢一把「持有者已死」的锁。
# 关键两点：
#  1) 获取 / 持锁 / 释放必须发生在同一个进程里，否则持有者一退出锁就该被接管，
#     测出来的「多个赢家」是测试假象；
#  2) common.sh 的 STATE 由 MODDIR 推导，测试用临时 MODDIR，不能直接覆盖 STATE。
#
# 判定方式不用挂钟：8 个进程并发 acquire，成功者先追加 "S"、睡 1 秒、释放前追加 "E"。
# 只要任意时刻持有者不超过 1 个，事件序列里就不会出现连续两个 S（深度 > 1）。
# 这样避免 CI 上 date +%s%N 精度/时钟非单调导致的假红（曾出现过一次）。
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi

TMP=$(mktemp -d)
MOD="$TMP/mod"
STATE="$MOD/state"
mkdir -p "$STATE" "$MOD/config"
BID="$TMP/boot_id"
echo "boot-A" > "$BID"
LOCK="$STATE/apply.lock"
EV="$TMP/events"
: > "$EV"

rm -rf "$LOCK"; mkdir -p "$LOCK"; echo "999999 boot-A" > "$LOCK/pid"

i=0
while [ $i -lt 8 ]; do
    (
        MODDIR="$MOD" PROC_BOOT_ID_FILE="$BID" EV="$EV" LOCK="$LOCK" REPO="$REPO" sh -c '
            . "$REPO/common.sh" >/dev/null 2>&1
            lock_acquire "$LOCK" 180 || exit 1
            printf "S\n" >> "$EV"
            sleep 1
            printf "E\n" >> "$EV"
            lock_release "$LOCK"
        ' >/dev/null 2>&1
    ) &
    i=$((i + 1))
done
wait

starts=$(grep -c "^S$" "$EV" 2>/dev/null || echo 0)
ends=$(grep -c "^E$" "$EV" 2>/dev/null || echo 0)
echo "抢到锁的进程数: $starts（E 事件 $ends 个）"

fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

# 深度检查：序列里任何时刻都不能有两个未配对的 S
maxdepth=$(awk '
    /^S$/ { d++; if (d > m) m = d }
    /^E$/ { if (d > 0) d-- }
    END   { print m+0 }' "$EV" 2>/dev/null)

chk "持有者从未超过 1 个" "$maxdepth" "1"
chk "至少有一个进程抢到" "$([ "$starts" -ge 1 ] && echo yes || echo no)" "yes"
chk "S/E 成对" "$starts" "$ends"

# 报告抢锁者数量（并发接管只应有少量赢家，主要看上面的互斥性）
echo "（信息）8 个并发里有 $starts 个成功获取锁"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
