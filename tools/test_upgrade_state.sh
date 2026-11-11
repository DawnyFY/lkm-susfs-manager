#!/bin/sh
# 升级版本时必须清掉上一版本的暂停/失败/守卫状态，否则新加载路径不会尝试。
set -u
REPO=${1:-.}
[ -d "$REPO/module" ] || { echo "FAIL  repo/module missing"; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
M="$TMP/mod"; mkdir -p "$M/state" "$M/config"
printf 'version=1.2.5\n' > "$M/module.prop"
touch "$M/state/autoload_paused" "$M/state/fail_count" "$M/state/loading" "$M/state/boot_guard"
( MODDIR="$M"; STATE="$M/state"; CONFIG="$M/config"; . "$REPO/module/common.sh"; clear_stale_state_on_upgrade )
fail=0
for f in autoload_paused fail_count loading boot_guard; do
    if [ -e "$M/state/$f" ]; then echo "FAIL  $f 未清理"; fail=1; else echo "PASS  $f 已清理"; fi
done
[ "$(cat "$M/state/last_version" 2>/dev/null)" = "1.2.5" ] && echo "PASS  last_version=1.2.5" || { echo "FAIL  last_version"; fail=1; }
touch "$M/state/autoload_paused"
( MODDIR="$M"; STATE="$M/state"; CONFIG="$M/config"; . "$REPO/module/common.sh"; clear_stale_state_on_upgrade )
[ -e "$M/state/autoload_paused" ] && echo "PASS  同版本保留暂停" || { echo "FAIL  同版本误清暂停"; fail=1; }
exit "$fail"
