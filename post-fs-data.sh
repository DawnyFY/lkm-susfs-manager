#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# 开机早期：只负责加载 LKM，规则留到 boot-completed 再应用。
MODDIR=/data/adb/modules/susfs_allinone
. "$MODDIR/common.sh"

boot_gate_ok || exit 0

cfg_ensure
cfg_load
# 配置不能改变模块路径与状态目录
MODDIR=/data/adb/modules/susfs_allinone
CONFIG=$MODDIR/config
STATE=$MODDIR/state
[ "${auto_load:-1}" = "1" ] || exit 0

# 守卫：上次加载后没能完成启动（panic/卡死），这次不再自动加载
if ! boot_guard_should_pause; then
    echo "=== post-fs-data: 暂停自动加载 ===" >> "$MODDIR/load.log" 2>/dev/null
    exit 0
fi

# 自动加载前落标记，只有 boot-completed 才会清除
mark_boot_guard "$(cat /proc/sys/kernel/osrelease 2>/dev/null)"

if command -v timeout >/dev/null 2>&1; then
    timeout 30 /system/bin/sh "$MODDIR/load.sh"
else
    /system/bin/sh "$MODDIR/load.sh"
fi