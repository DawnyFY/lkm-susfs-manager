#!/bin/sh
# 离线回归：ctl.sh status 的输出字段必须与 fixtures/status.baseline 一致
#  - 集合：不能少字段（重构漏字段）
#  - 顺序：status() 内字段顺序必须与基线一致，首字段必须是 module_version
# 目的：为重构 status（ISS-001：去掉多余 fork）提供可验证护栏。
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi
BASE="$ROOT/tools/fixtures/status.baseline"
CTL="$REPO/ctl.sh"

[ -f "$BASE" ] || { echo "SKIP  缺少基线文件"; exit 0; }
[ -f "$CTL" ] || { echo "FAIL  找不到 ctl.sh"; exit 1; }

fail=0

emit_keys=$(
    {
        awk '/^status\(\) \{/,/^\}/' "$CTL"
        awk '/^pg_status_fields\(\)/,/^\}/' "$CTL"
    } | grep -oE "printf '[a-z_]+=" | sed "s/printf '//; s/=$//" | sort -u
)
base_keys=$(sed -n '/^\[keys\]/,/^\[volatile\]/p' "$BASE" | grep -vE '^\s*#|^\s*\[|^\s*$' | sort -u)
base_order=$(sed -n '/^\[keys\]/,/^\[volatile\]/p' "$BASE" | grep -vE '^\s*#|^\s*\[|^\s*$')

# 1) 集合：基线里的每个字段仍要输出
for k in $base_keys; do
    if ! printf '%s\n' "$emit_keys" | grep -qx "$k"; then
        echo "FAIL  ctl.sh 不再输出字段: $k"
        fail=1
    fi
done

# 2) 顺序：只看 status() 本体（pg_status_fields 的字段在中间插入，单独排除）
status_body=$(awk '/^status\(\) \{/,/^\}/' "$CTL")
status_order=$(printf '%s\n' "$status_body" \
    | grep -oE "printf '[a-z_]+=" | sed "s/printf '//; s/=$//" | awk '!seen[$0]++')
base_status_order=$(printf '%s\n' "$base_order" | while IFS= read -r k; do
    printf '%s\n' "$status_order" | grep -qx "$k" && printf '%s\n' "$k"
done)

if [ -n "$status_order" ] && [ "$status_order" != "$base_status_order" ]; then
    echo "FAIL  status() 字段顺序与基线不一致"
    printf '%s\n' "$status_order" > "$ROOT/.status_order.$$"
    printf '%s\n' "$base_status_order" > "$ROOT/.status_base.$$"
    diff "$ROOT/.status_base.$$" "$ROOT/.status_order.$$" | head -8
    rm -f "$ROOT/.status_order.$$" "$ROOT/.status_base.$$"
    fail=1
fi

# 3) 首字段锚点
first_base=$(printf '%s\n' "$base_order" | head -1)
first_out=$(printf '%s\n' "$status_order" | head -1)
if [ "$first_base" != "$first_out" ]; then
    echo "FAIL  status 首个字段应为 $first_base（实际 $first_out）"
    fail=1
fi

[ "$fail" = 0 ] && echo "status keys OK ($(printf '%s\n' "$base_keys" | wc -l | tr -d ' ') 字段：集合与顺序一致)"
exit "$fail"
