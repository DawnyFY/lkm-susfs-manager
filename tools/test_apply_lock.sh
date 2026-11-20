#!/bin/sh
# 离线回归：apply 锁
#  1) 首次获取成功
#  2) 持有者进程存活 → 拒绝
#  3) 持有者进程已死 → 立即接管（不必等 TTL）
#  4) 跨 boot → 立即接管
#  5) 只有持有者自己能释放
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi

TMP=$(mktemp -d)
STATE="$TMP/state"
mkdir -p "$STATE"
BID="$TMP/boot_id"
echo "boot-A" > "$BID"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

# 一次 acquire，返回退出码（子 shell 的 PID 就是锁的持有者，随子 shell 退出而消失）
acq() {
    PROC_BOOT_ID_FILE="$BID" STATE="$STATE" sh -c ". '$REPO/common.sh' >/dev/null 2>&1; lock_acquire '$STATE/apply.lock' 180" >/dev/null 2>&1
    echo $?
}

# 1) 首次获取
chk "首次获取成功" "$(acq)" "0"
chk "锁目录已建" "$([ -d "$STATE/apply.lock" ] && echo yes || echo no)" "yes"
chk "锁里记录了 boot_id" "$(cut -d' ' -f2 "$STATE/apply.lock/pid")" "boot-A"

# 2) 持有者存活：用一个真实的后台进程当持有者
sleep 30 &
LIVE=$!
echo "$LIVE boot-A" > "$STATE/apply.lock/pid"
chk "持有者存活时拒绝" "$(acq)" "1"
chk "被拒后锁内容未变" "$(cut -d' ' -f1 "$STATE/apply.lock/pid")" "$LIVE"

# 3) 持有者已死：换成一个不存在的 PID
kill "$LIVE" 2>/dev/null
wait "$LIVE" 2>/dev/null
echo "999999 boot-A" > "$STATE/apply.lock/pid"
chk "死进程锁被立即接管" "$(acq)" "0"
chk "接管后 pid 已换成新持有者" "$([ "$(cut -d' ' -f1 "$STATE/apply.lock/pid")" = "999999" ] && echo stale || echo fresh)" "fresh"

# 4) 跨 boot：持有者 PID 存活但 boot_id 不同
sleep 30 &
LIVE2=$!
echo "$LIVE2 boot-B" > "$STATE/apply.lock/pid"
chk "跨 boot 立即接管" "$(acq)" "0"
kill "$LIVE2" 2>/dev/null
wait "$LIVE2" 2>/dev/null

# 5) 只有持有者能释放：别人来释放应当无效
echo "999998 boot-A" > "$STATE/apply.lock/pid"
PROC_BOOT_ID_FILE="$BID" STATE="$STATE" sh -c ". '$REPO/common.sh' >/dev/null 2>&1; lock_release '$STATE/apply.lock'" >/dev/null 2>&1
chk "非持有者释放无效" "$([ -d "$STATE/apply.lock" ] && echo kept || echo removed)" "kept"

# 自己释放（在同一子 shell 里 acquire 再 release）
PROC_BOOT_ID_FILE="$BID" STATE="$STATE" sh -c ". '$REPO/common.sh' >/dev/null 2>&1; rm -rf '$STATE/apply.lock'; lock_acquire '$STATE/apply.lock' 180 && lock_release '$STATE/apply.lock'" >/dev/null 2>&1
chk "持有者释放后目录消失" "$([ -d "$STATE/apply.lock" ] && echo kept || echo removed)" "removed"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
