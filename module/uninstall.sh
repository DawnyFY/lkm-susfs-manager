#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# 卸载钩子：KernelSU/Magisk 会删除模块目录本身，这里只清理模块在开机后
# 可能残留在其它位置的运行痕迹，并尽量让内核侧规则回到"未隐藏"状态。
# 不触碰 /data/adb/modules 下的其它模块。
MODDIR=/data/adb/modules/susfs_allinone

log() { echo "[uninstall] $*"; }

# 1) 尽量撤销本模块下发过的 sus_path 规则（LKM 还在的情况下）
if [ -e /proc/susfs_path ] && [ -s "$MODDIR/state/our_paths.txt" ]; then
    while IFS= read -r p || [ -n "$p" ]; do
        [ -n "$p" ] || continue
        echo "del $p" >> /proc/susfs_path 2>/dev/null
    done < "$MODDIR/state/our_paths.txt"
    log "已尝试撤销 $(wc -l < "$MODDIR/state/our_paths.txt" 2>/dev/null) 条 sus_path 规则"
fi

# 2) 清隐藏名单里本模块加过的名字
if [ -e /proc/susfs_hide_modules ]; then
    for n in generic_pid_guard; do
        grep -qw -- "$n" /proc/susfs_hide_modules 2>/dev/null && echo "del $n" > /proc/susfs_hide_modules 2>/dev/null
    done
fi

# 3) 删运行期文件（config 保留在模块目录里，随目录一起被管理器删除）
rm -f "$MODDIR"/*.log "$MODDIR"/*.log.1 2>/dev/null
rm -rf "$MODDIR"/state 2>/dev/null
log "已清理运行期日志与 state/"

# 4) 删除自动加载抑制标记，避免残留影响其它判断
rm -f "$MODDIR/disable_autoload" 2>/dev/null

log "完成。config/ 目录保留在模块目录中，随模块删除一并移除。"
exit 0
