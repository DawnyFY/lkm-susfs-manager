#!/bin/sh
# 并发接管的回归：多个进程同时抢一把「持有者已死」的锁。
# 关键：获取 / 持锁 / 释放必须发生在同一个进程里，否则持有者一退出锁就该被接管，
# 测出来的「多个赢家」是测试假象而非竞态。
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi

TMP=$(mktemp -d)
STATE="$TMP/state"
mkdir -p "$STATE"
BID="$TMP/boot_id"
echo "boot-A" > "$BID"
LOCK="$STATE/apply.lock"
HELD="$TMP/held"
: > "$HELD"

rm -rf "$LOCK"; mkdir -p "$LOCK"; echo "999999 boot-A" > "$LOCK/pid"

i=0
while [ $i -lt 8 ]; do
    (
        PROC_BOOT_ID_FILE="$BID" STATE="$STATE" HELD="$HELD" LOCK="$LOCK" REPO="$REPO" sh -c '
            . "$REPO/common.sh" >/dev/null 2>&1
            lock_acquire "$LOCK" 180 || exit 1
            _s=$(date +%s%N)
            sleep 1
            _e=$(date +%s%N)
            printf "%s %s\n" "$_s" "$_e" >> "$HELD"
            lock_release "$LOCK"
        ' >/dev/null 2>&1
    ) &
    i=$((i + 1))
done
wait

held=$(wc -l < "$HELD" 2>/dev/null || echo 0)
echo "抢到锁的进程数: $held"

fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

overlap=$(sort -n "$HELD" 2>/dev/null | awk '
    { s=$1; e=$2; if (s < last_end) { n++ } if (e > last_end) last_end=e }
    END { print n+0 }')
chk "持锁窗口无重叠" "$overlap" "0"
chk "至少有一个拿到锁" "$([ "$held" -ge 1 ] && echo yes || echo no)" "yes"
chk "锁已被释放" "$([ -d "$LOCK" ] && echo kept || echo released)" "released"
chk "互斥目录已清理" "$([ -d "$STATE/.lock.mutex" ] && echo kept || echo clean)" "clean"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
