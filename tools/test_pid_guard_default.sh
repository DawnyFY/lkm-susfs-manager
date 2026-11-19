#!/bin/sh
# Probe PID Guard 默认值回归：1.2.8 起出厂默认关闭，且升级时只迁移"未改过"的配置
set -u
REPO=${1:-.}
M="$REPO/module"
pass=0
fail=0
ok() { pass=$((pass + 1)); }
bad() { echo "FAIL: $*"; fail=$((fail + 1)); }

# 1) 出厂模板 enabled=0
if grep -qx 'enabled=0' "$M/config/pid_guard.conf" 2>/dev/null; then
    ok
else
    bad "config/pid_guard.conf 的 enabled 不是 0"
fi

# 2) pid_guard.sh：enabled 非 1 一律视为关闭
if grep -q 'case "$ENABLED" in 1) ;; \*) ENABLED=0 ;; esac' "$M/pid_guard.sh" 2>/dev/null; then
    ok
else
    bad "pid_guard.sh 缺少 enabled 归一化"
fi

# 3) customize.sh 有迁移块，且迁移用的旧模板字面量完整
if grep -q '1.2.8：Probe PID Guard 默认改为关闭' "$M/customize.sh" 2>/dev/null; then
    ok
else
    bad "customize.sh 缺少默认值迁移块"
fi
for lit in 'enabled=1' 'target_uids=99000-99999' 'target_comms=probe-*,canProbe*,ivecheck*'; do
    if grep -qF -- "$lit" "$M/customize.sh" 2>/dev/null; then
        ok
    else
        bad "迁移块缺少旧模板字面量: $lit"
    fi
done

# 4) 迁移只在"旧配置 = 出厂原样"时发生（比对 cat 全文，不按行匹配）
if grep -q 'if \[ "$(cat "$INSTALLED/config/pid_guard.conf" 2>/dev/null)" = "$_pg_old" \]' "$M/customize.sh" 2>/dev/null; then
    ok
else
    bad "迁移条件不是整文件比对（会误伤用户改过的配置）"
fi

# 5) 出厂模板备份在覆盖前完成，且用完即删
if grep -q '_pg_tpl_bak="$MODPATH/config/.pid_guard.conf.new"' "$M/customize.sh" 2>/dev/null &&
   grep -q 'rm -f "$_pg_tpl_bak"' "$M/customize.sh" 2>/dev/null; then
    ok
else
    bad "缺少模板备份或清理"
fi

echo "pid_guard default: PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] || exit 1
