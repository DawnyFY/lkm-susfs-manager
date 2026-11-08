#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Magisk 兼容入口：Magisk 没有 boot-completed，规则在 service（late_start）阶段应用。
# KernelSU / APatch 仍走 boot-completed.sh，这里直接跳过，避免重复应用。
MODDIR=/data/adb/modules/susfs_allinone
. "$MODDIR/common.sh"

boot_gate_ok || exit 0

# 应用规则前校验：文件被改过就不下发规则
_cf_gate || { echo "=== service: 文件被修改，跳过应用 ===" >> "$MODDIR/apply.log" 2>/dev/null; exit 0; }

case "$(root_family)" in
    KernelSU|APatch) exit 0 ;;
esac

cfg_ensure
cfg_load
[ "${auto_load:-1}" = "1" ] || exit 0

# 与 boot-completed 一致：只有应用真正跑完才清除开机守卫标记。
# 少了这一步，Magisk 下守卫永远不会清除，下一次开机会误判为“上次没启动成功”。
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
