#!/bin/sh
# 离线回归：apply 锁
#  1) 首次获取成功
#  2) 持有者进程存活 → 拒绝
#  3) 持有者进程已死 → 立即接管（不必等 TTL）
#  4) 跨 boot → 立即接管
#  5) 只有持有者自己能释放
#
# 注意：common.sh 里 STATE 是从 MODDIR 推导的（不允许用环境变量指到模块外），
# 所以测试用一个临时 MODDIR，而不是直接覆盖 STATE。
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
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

# 在独立的 MODDIR 下跑一小段逻辑；$1 = 要执行的 shell 片段
run() {
    MODDIR="$MOD" PROC_BOOT_ID_FILE="$BID" sh -c ". '$REPO/common.sh' >/dev/null 2>&1; $1"
}

acq() {
    run "lock_acquire '$LOCK' 180" >/dev/null 2>&1
    echo $?
}

# 1) 首次获取
chk "首次获取成功" "$(acq)" "0"
chk "锁目录已建" "$([ -d "$LOCK" ] && echo yes || echo no)" "yes"
chk "锁里记录了 boot_id" "$(cut -d' ' -f2 "$LOCK/pid")" "boot-A"

# 2) 持有者存活：用一个真实的后台进程当持有者
sleep 30 &
LIVE=$!
echo "$LIVE boot-A" > "$LOCK/pid"
chk "持有者存活时拒绝" "$(acq)" "1"
chk "被拒后锁内容未变" "$(cut -d' ' -f1 "$LOCK/pid")" "$LIVE"

# 3) 持有者已死：换成一个不存在的 PID
kill "$LIVE" 2>/dev/null
wait "$LIVE" 2>/dev/null
echo "999999 boot-A" > "$LOCK/pid"
chk "死进程锁被立即接管" "$(acq)" "0"
chk "接管后 pid 已换成新持有者" "$([ "$(cut -d' ' -f1 "$LOCK/pid")" = "999999" ] && echo stale || echo fresh)" "fresh"

# 4) 跨 boot：持有者 PID 存活但 boot_id 不同
sleep 30 &
LIVE2=$!
echo "$LIVE2 boot-B" > "$LOCK/pid"
chk "跨 boot 立即接管" "$(acq)" "0"
kill "$LIVE2" 2>/dev/null
wait "$LIVE2" 2>/dev/null

# 5) 只有持有者能释放：别人来释放应当无效
echo "999998 boot-A" > "$LOCK/pid"
run "lock_release '$LOCK'" >/dev/null 2>&1
chk "非持有者释放无效" "$([ -d "$LOCK" ] && echo kept || echo removed)" "kept"

# 自己释放（同一进程里 acquire 再 release）
run "rm -rf '$LOCK'; lock_acquire '$LOCK' 180 && lock_release '$LOCK'" >/dev/null 2>&1
chk "持有者释放后目录消失" "$([ -d "$LOCK" ] && echo kept || echo removed)" "removed"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
