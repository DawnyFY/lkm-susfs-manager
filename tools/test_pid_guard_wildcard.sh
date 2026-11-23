#!/bin/sh
# 回归：pid_guard 的 comm 通配只允许「尾部一个 *」（audit-legacy m7）
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi
CTL="$REPO/pid_guard_ctl.sh"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

TMP=$(mktemp -d)
try() {
    printf 'enabled=1\ntarget_uids=\ntarget_comms=%s\nexclude_comms=\n' "$1" > "$TMP/c.conf"
    sh -c '. "'"$CTL"'" >/dev/null 2>&1; validate "'"$TMP"'/c.conf" >/dev/null 2>&1' && echo OK || echo REJECT
}

chk "sh* 允许（尾部通配）" "$(try 'sh*')" "OK"
chk "sh 允许（精确）" "$(try 'sh')" "OK"
chk "sh,foo* 允许" "$(try 'sh,foo*')" "OK"
chk "* 拒绝（裸通配）" "$(try '*')" "REJECT"
chk "*sh 拒绝（前缀通配）" "$(try '*sh')" "REJECT"
chk "*a* 拒绝（中间通配）" "$(try '*a*')" "REJECT"
chk "sh*bash 拒绝（中间通配）" "$(try 'sh*bash')" "REJECT"
chk "*.su* 拒绝" "$(try '*.su*')" "REJECT"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
