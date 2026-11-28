#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
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
dmesg_crash_capture 2>/dev/null || true
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
# LKM 掉线看护：系统 OOM 或别的工具 rmmod 后，按上次配置重载。
# 频率由 config.ini 的 watchdog_minutes 控制（0=关闭，默认 0，避免无谓唤醒）。
WD=$(conf_get watchdog_minutes "$CONFIG/config.ini" 2>/dev/null)
case "$WD" in ''|*[!0-9]*) WD=0 ;; esac
if [ "$WD" -gt 0 ] 2>/dev/null; then
    (
        _wd_n=0
        while :; do
            sleep $((WD * 60)) 2>/dev/null || exit 0
            _wd_n=$((_wd_n + 1))
            if [ ! -d /sys/module/susfs_guard_lkm ] && [ ! -e /proc/susfs_path ]; then
                echo "[!] $(date '+%F %T' 2>/dev/null) LKM 不在（第 $_wd_n 次检查），尝试重载" >> "$MODDIR/apply.log" 2>/dev/null
                AUTOLOAD=1 sh "$MODDIR/apply.sh" >> "$MODDIR/apply.log" 2>&1 || true
            fi
        done
    ) &
fi

exit "$rc"
