#!/bin/sh
# 回归：apply 正在跑时写配置应该等待而不是立刻报 busy（audit-legacy m6）
#  1 空闲时立即拿到
#  2 锁被活进程持有时，默认刻度（约 2s）失败
#  3 同一个锁换成大刻度（10s），持有者退出后能接管
#  4 结构断言：写配置的两个入口确实用了更长的等待
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi

TMP=$(mktemp -d)
MOD="$TMP/mod"
mkdir -p "$MOD/state" "$MOD/config"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

export MODDIR="$MOD"
. "$REPO/common.sh" >/dev/null 2>&1
LOCK="$MOD/state/apply.lock"
BIDF="${PROC_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}"

# 1) 空闲
lock_acquire "$LOCK" 180 >/dev/null 2>&1
chk "空闲时拿到锁" "$?" "0"
lock_release "$LOCK"

# 2/3) 造一个活着的持有者（sleep 30 的 pid 写进锁）
sleep 30 &
HOLD=$!
mkdir -p "$LOCK"
printf '%s %s\n' "$HOLD" "$(cat "$BIDF" 2>/dev/null)" > "$LOCK/pid"

lock_acquire "$LOCK" 180 >/dev/null 2>&1
chk "活持有者 + 默认刻度 → 失败" "$?" "1"
chk "锁仍在（没被误删）" "$([ -d "$LOCK" ] && echo kept || echo gone)" "kept"

# 持有者退出后，用大刻度接管（这里持有者已死，等价于"等到对方释放"）
kill "$HOLD" 2>/dev/null
wait "$HOLD" 2>/dev/null
sleep 0.2
t0=$(date +%s)
lock_acquire "$LOCK" 180 200 >/dev/null 2>&1
rc=$?
t1=$(date +%s)
chk "持有者退出后能接管" "$rc" "0"
chk "接管耗时可忽略（<5s）" "$([ $((t1 - t0)) -lt 5 ] && echo ok || echo no)" "ok"

# 4) 结构断言
C="$REPO/ctl.sh"
chk "set_bundle 等 20s（400 刻度）" "$(grep -c 'lock_acquire "\$STATE/apply.lock" 900 400' "$C")" "1"
chk "set_config 等 10s（200 刻度，TTL 180）" "$(grep -c 'lock_acquire "\$STATE/apply.lock" 180 200' "$C")" "1"
chk "lock_acquire 支持第 3 个参数" "$(grep -c '_waits=\${3:-40}' "$REPO/common.sh")" "1"
chk "主锁也在重试循环里" "$(grep -c 'if \[ ! -e "\$_lk" \] && mkdir "\$_lk"' "$REPO/common.sh")" "1"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
