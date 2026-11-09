#!/bin/sh
# 离线测试：_cf 完整性校验的缓存/跳过逻辑
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }
M="$TMP/mod"; mkdir -p "$M"
printf "hello\n" > "$M/a.txt"; printf "world\n" > "$M/b.txt"
touch -t 202001010000 "$M/a.txt" "$M/b.txt"
H1=$(sha256sum "$M/a.txt" | cut -d" " -f1)
H2=$(sha256sum "$M/b.txt" | cut -d" " -f1)
printf "%s  %s\n%s  %s\n" "$H1" a.txt "$H2" b.txt > "$M/.cache.files"
printf 'test-boot\n' > "$TMP/bid"
run_cf() { ( MODDIR="$M"; PROC_BOOT_ID_FILE="$TMP/bid"; . "$REPO/common.sh"; _cf; echo "rc=$?" ) }

out=$(run_cf); chk "首次校验通过" "$(printf "%s" "$out" | tail -1)" "rc=0"
chk "生成缓存" "$([ -f "$M/state/.cf.ok" ] && echo yes || echo no)" "yes"
out=$(run_cf); chk "第二次命中缓存" "$(printf "%s" "$out" | tail -1)" "rc=0"
printf "tampered-backdated\n" > "$M/a.txt"; touch -t 202001010000 "$M/a.txt"
out=$(run_cf); chk "改文件并回拨 mtime 仍拒绝" "$(printf "%s" "$out" | tail -1)" "rc=1"
printf "hello\n" > "$M/a.txt"; touch -t 202001010000 "$M/a.txt"; rm -f "$M/state/.cf.ok"
out=$(run_cf); chk "恢复后重新校验通过(2)" "$(printf "%s" "$out" | tail -1)" "rc=0"
out=$( ( export SUSFS_CF_OK=1; MODDIR="$M"; PROC_BOOT_ID_FILE="$TMP/bid"; . "$REPO/common.sh"; _cf; echo "rc=$?" ) )
chk "SUSFS_CF_OK 环境跳过" "$(printf "%s" "$out" | tail -1)" "rc=0"

printf "tampered\n" > "$M/a.txt"
out=$(run_cf); chk "内容被改后拒绝" "$(printf "%s" "$out" | tail -1)" "rc=1"

printf "hello\n" > "$M/a.txt"; touch -t 202001010000 "$M/a.txt"
rm -f "$M/state/.cf.ok"
out=$(run_cf); chk "恢复后重新校验通过" "$(printf "%s" "$out" | tail -1)" "rc=0"

rm -f "$M/b.txt" "$M/state/.cf.ok"
out=$(run_cf); chk "文件缺失被拒绝" "$(printf "%s" "$out" | tail -1)" "rc=1"

rm -rf "$TMP"
exit "$fail"
