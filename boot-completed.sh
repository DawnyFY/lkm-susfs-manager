#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# 开机完成：应用 sus_path / hide_modules 等规则（每次开机只执行一次）。
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

# 只执行一次应用；只有真正跑完（rc=0）才认为本次启动成功，清除守卫标记。
# 开机早期尚不存在的应用数据目录不会重试，需要时在 WebUI 手动「加载并应用」补一次。
AUTOLOAD=1 sh "$MODDIR/apply.sh"
rc=$?
if [ "$rc" = "0" ]; then
    clear_boot_guard
fi

exit "$rc"