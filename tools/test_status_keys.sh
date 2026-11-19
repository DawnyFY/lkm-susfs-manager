#!/bin/sh
# 离线回归：ctl.sh status 的输出键必须覆盖 fixtures/status.baseline 里记录的集合
# 目的：重构 status（ISS-001：去掉多余 fork）时漏字段能被立刻发现。
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi
BASE="$ROOT/tools/fixtures/status.baseline"
CTL="$REPO/ctl.sh"

[ -f "$BASE" ] || { echo "SKIP  缺少基线文件"; exit 0; }
[ -f "$CTL" ] || { echo "FAIL  找不到 ctl.sh"; exit 1; }

fail=0
miss=0

# status() + pg_status_fields() 里所有 printf 'key=...' 的键名
emit_keys=$(
    {
        awk '/^status\(\) \{/,/^\}/' "$CTL"
        awk '/^pg_status_fields\(\)/,/^\}/' "$CTL"
    } | grep -oE "printf '[a-z_]+=" | sed "s/printf '//; s/=$//" | sort -u
)

# 基线里的键（跳过注释/段落标记）
base_keys=$(sed -n '/^\[keys\]/,/^\[volatile\]/p' "$BASE" | grep -vE '^\s*#|^\s*\[|^\s*$' | sort -u)

for k in $base_keys; do
    if ! printf '%s\n' "$emit_keys" | grep -qx "$k"; then
        echo "FAIL  ctl.sh 不再输出字段: $k"
        miss=$((miss + 1))
        fail=1
    fi
done

[ "$fail" = 0 ] && echo "status keys OK ($(printf '%s\n' "$base_keys" | wc -l | tr -d ' ') 个字段)"
exit "$fail"
