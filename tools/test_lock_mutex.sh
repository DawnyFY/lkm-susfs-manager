#!/bin/sh
# 回归：state/.lock.mutex 残留必须能被回收（audit B2，1.2.9 起就存在）
# 旧实现只认「pid 是数字且 /proc 不存在」，以下场景会永久卡死：
#   pid 缺失 / pid 为空 / pid 是垃圾串 / pid 被别的进程复用 / mutex 很久没动
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
MUTEX="$STATE/.lock.mutex"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

acq() {
    MODDIR="$MOD" PROC_BOOT_ID_FILE="$BID" sh -c ". '$REPO/common.sh' >/dev/null 2>&1; lock_acquire '$LOCK' 180" >/dev/null 2>&1
    echo $?
}

reset() { rm -rf "$LOCK" "$MUTEX"; mkdir -p "$MUTEX"; }

# 1) pid 文件不存在（apply 在 mkdir 与写 pid 之间被杀）
reset
touch -d "10 seconds ago" "$MUTEX" 2>/dev/null || true
chk "pid 缺失 + 已过 2s → 回收" "$(acq)" "0"
chk "回收后 mutex 已清" "$([ -d "$MUTEX" ] && echo kept || echo clean)" "clean"

# 2) pid 为空文件
reset
: > "$MUTEX/pid"
touch -d "10 seconds ago" "$MUTEX" 2>/dev/null || true
chk "pid 为空 + 已过 2s → 回收" "$(acq)" "0"

# 3) pid 是垃圾串（例如被写坏）
reset
printf 'abc\n' > "$MUTEX/pid"
touch -d "10 seconds ago" "$MUTEX" 2>/dev/null || true
chk "pid 损坏 + 已过 2s → 回收" "$(acq)" "0"

# 4) pid 被别的进程复用（进程活着，但不是锁的持有者）
reset
sleep 30 &
LIVE=$!
echo "$LIVE" > "$MUTEX/pid"
touch -d "60 seconds ago" "$MUTEX" 2>/dev/null || true
chk "pid 复用但 mutex 已超 30s → 回收" "$(acq)" "0"
kill "$LIVE" 2>/dev/null; wait "$LIVE" 2>/dev/null

# 5) 刚创建、pid 活着 → 必须尊重它（不能抢）
reset
sleep 30 &
LIVE2=$!
echo "$LIVE2" > "$MUTEX/pid"
chk "新 mutex + 活持有者 → 拒绝" "$(acq)" "1"
kill "$LIVE2" 2>/dev/null; wait "$LIVE2" 2>/dev/null
rm -rf "$MUTEX" "$LOCK"

# 6) 正常路径不受影响
chk "无 mutex 时正常获取" "$(acq)" "0"
chk "锁目录已建" "$([ -d "$LOCK" ] && echo yes || echo no)" "yes"
chk "mutex 已释放" "$([ -d "$MUTEX" ] && echo kept || echo clean)" "clean"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
