#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# 开机完成：应用 sus_path / hide_modules 等规则（每次开机只执行一次）。
MODDIR=/data/adb/modules/susfs_allinone
. "$MODDIR/common.sh"

boot_gate_ok || exit 0

# 应用规则前校验：文件被改过就不下发规则
_cf_gate || { echo "=== boot-completed: 文件被修改，跳过应用 ===" >> "$MODDIR/apply.log" 2>/dev/null; exit 0; }

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
case "$rc" in
    0) clear_boot_guard ;;
    5) echo "[!] 规则部分失败（rc=5），本 boot 已完成，详见 apply.log"
       clear_boot_guard ;;
esac
case "$rc" in
    0|5) printf '%s %s\n' "$(date '+%F %T' 2>/dev/null)" "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)" > "$STATE/boot_stage_completed" 2>/dev/null ;;
esac

exit "$rc"