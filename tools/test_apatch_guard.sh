#!/bin/sh
# 离线测试：APatch 防护（默认不放行外挂 LKM、pstore 崩溃探测、入口接入）
set -u
REPO="$1"
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }
M="$TMP/mod"; mkdir -p "$M/state" "$M/config"

# 1) apatch_lkm_allowed
out=$( ( MODDIR="$M"; . "$REPO/common.sh"; apatch_lkm_allowed && echo yes || echo no ) )
chk "默认不放行外挂 LKM" "$out" "no"
touch "$M/config/allow_lkm_on_kernelpatch"
out=$( ( MODDIR="$M"; . "$REPO/common.sh"; apatch_lkm_allowed && echo yes || echo no ) )
chk "allow 标记后放行" "$out" "yes"

# 2) pstore_crash_suspect
PS="$TMP/pstore"; mkdir -p "$PS"
out=$( ( MODDIR="$M"; PSTORE_DIR="$PS"; . "$REPO/common.sh"; pstore_crash_suspect && echo yes || echo no ) )
chk "无 pstore 文件 → no" "$out" "no"
printf "normal boot log\n" > "$PS/console-ramoops-0"
out=$( ( MODDIR="$M"; PSTORE_DIR="$PS"; . "$REPO/common.sh"; pstore_crash_suspect && echo yes || echo no ) )
chk "普通日志 → no" "$out" "no"
printf "susfs_guard_lkm: loaded\n" > "$PS/console-ramoops-0"
out=$( ( MODDIR="$M"; PSTORE_DIR="$PS"; . "$REPO/common.sh"; pstore_crash_suspect && echo yes || echo no ) )
chk "只有 susfs 日志 → no" "$out" "no"
printf "Kernel panic - not syncing: test\n" > "$PS/console-ramoops-0"
out=$( ( MODDIR="$M"; PSTORE_DIR="$PS"; . "$REPO/common.sh"; pstore_crash_suspect && echo yes || echo no ) )
chk "只有 panic → no" "$out" "no"
printf "Kernel panic - not syncing: test\nsusfs_guard_lkm: x\n" > "$PS/console-ramoops-0"
out=$( ( MODDIR="$M"; PSTORE_DIR="$PS"; . "$REPO/common.sh"; pstore_crash_suspect && echo yes || echo no ) )
chk "panic+susfs → yes" "$out" "yes"

# 3) 入口是否接入防护
chk "load.sh 接入 APatch 防护" "$(grep -c "apatch_lkm_allowed" "$REPO/load.sh")" "1"
chk "apply.sh 接入 APatch 防护" "$(grep -c "apatch_lkm_allowed" "$REPO/apply.sh")" "1"
chk "ctl.sh 提供 allow_lkm" "$(grep -c "^    allow_lkm)" "$REPO/ctl.sh")" "1"

rm -rf "$TMP"
exit "$fail"
