#!/bin/sh
# 离线测试：apply 互斥锁与过期自愈
set -u
REPO="$1"
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }
MODDIR="$TMP"; mkdir -p "$TMP/config" "$TMP/state"
. "$REPO/common.sh"

LK="$STATE/apply.lock"
chk "首次获取" "$(lock_acquire "$LK" 900 && echo ok || echo no)" "ok"
chk "重复获取被拒" "$(lock_acquire "$LK" 900 && echo ok || echo no)" "no"
lock_release "$LK"
chk "释放后可再取" "$(lock_acquire "$LK" 900 && echo ok || echo no)" "ok"

# 过期锁：把 mtime 改到 20 分钟前
touch -d '20 minutes ago' "$LK"
chk "过期锁可接管" "$(lock_acquire "$LK" 900 && echo ok || echo no)" "ok"
lock_release "$LK"

# 锁归属：别人的锁不能被自己释放
mkdir -p "$LK"; echo 999999 > "$LK/pid"
lock_release "$LK"
chk "非本人锁不释放" "$(ls -d "$LK" 2>/dev/null | wc -l | tr -d " ")" "1"
rm -rf "$LK"

# 自己的锁可以释放
lock_acquire "$LK" 900
chk "本人锁可释放" "$(lock_release "$LK"; ls -d "$LK" 2>/dev/null | wc -l | tr -d " ")" "0"

# 并发接管：两个进程同时判定同一把锁过期，只能有一个成功
rm -rf "$LK"; mkdir -p "$LK"; echo 999999 > "$LK/pid"
touch -d "20 minutes ago" "$LK"
R1=$(lock_acquire "$LK" 900 && echo ok || echo no)
R2=$(lock_acquire "$LK" 900 && echo ok || echo no)
chk "并发接管只有一个成功" "$([ "$R1" != "$R2" ] && echo yes || echo no)" "yes"
rm -rf "$LK"/*.tmp "$STATE"/.lock.stale.* 2>/dev/null

# file_older_than
: > "$TMP/new"; touch -d "20 minutes ago" "$TMP/old"
chk "新文件不算旧" "$(file_older_than "$TMP/new" 600 && echo old || echo new)" "new"
chk "旧文件判旧" "$(file_older_than "$TMP/old" 600 && echo old || echo new)" "old"
chk "文件缺失不报旧" "$(file_older_than "$TMP/missing" 600 && echo old || echo new)" "new"

# 集成断言：apply.sh 必须真的用了锁与自愈
chk "apply 使用锁" "$(grep -c 'lock_acquire "$STATE/apply.lock"' "$REPO/apply.sh")" "1"
chk "apply 释放锁" "$(grep -c "trap 'lock_release" "$REPO/apply.sh")" "1"
chk "自愈不再用 find -mmin" "$(grep -c 'mmin' "$REPO/apply.sh" || true)" "0"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"