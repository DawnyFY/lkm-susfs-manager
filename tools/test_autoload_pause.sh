#!/bin/sh
# 回归：clear_boot_guard 与 autoload_paused 的语义拆分（F1）
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi
TMP=$(mktemp -d)
M="$TMP/m"; mkdir -p "$M/state"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }
run_common() { ( MODDIR="$M"; STATE="$M/state"; . "$REPO/common.sh"; eval "$1" ); }

run_common 'pause_autoload; : > "$(boot_guard_path)"; clear_boot_guard_keep_pause'
chk "keep_pause 清 guard 但保留暂停" "$([ -f "$M/state/autoload_paused" ] && echo yes || echo no)" "yes"
chk "keep_pause 清掉 boot_guard" "$([ -f "$M/state/boot_guard" ] && echo yes || echo no)" "no"

run_common 'pause_autoload; : > "$(boot_guard_path)"; clear_boot_guard'
chk "clear_boot_guard 同时清暂停" "$([ -f "$M/state/autoload_paused" ] && echo yes || echo no)" "no"

cat > "$TMP/fail.body" <<'BODY'
set_description() { :; }
note_fail() {
    n=$(cat "$STATE/fail_count" 2>/dev/null)
    n=${n:-0}
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    n=$((n + 1))
    echo "$n" > "$STATE/fail_count"
}
BODY
sed -n '/^fail()/,/^}/p' "$REPO/load.sh" >> "$TMP/fail.body"
( MODDIR="$M"; STATE="$M/state"; . "$REPO/common.sh"; . "$TMP/fail.body"; echo 2 > "$STATE/fail_count"; ( fail "boom" >/dev/null 2>&1 ) )
chk "fail 第 3 次后暂停仍在" "$([ -f "$M/state/autoload_paused" ] && echo yes || echo no)" "yes"
chk "fail 第 3 次后 boot_guard 已清" "$([ -f "$M/state/boot_guard" ] && echo yes || echo no)" "no"

( MODDIR="$M"; STATE="$M/state"; . "$REPO/common.sh"; . "$TMP/fail.body"; echo 0 > "$STATE/fail_count"; pause_autoload; ( fail "preflight" >/dev/null 2>&1 ) )
chk "fail 保留已有暂停" "$([ -f "$M/state/autoload_paused" ] && echo yes || echo no)" "yes"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
