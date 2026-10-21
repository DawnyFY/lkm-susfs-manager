#!/system/bin/sh
# 共享的 root 管理器与 ksu_susfs 路径检测。
# 兼容 KernelSU 官方版及 SukiSU / ReSukiSU / KernelSU Next 等分支，
# 也兼容 APatch 的二进制目录（模块安装仍以 KernelSU 系列为主）。

MODDIR=${MODDIR:-/data/adb/modules/susfs_allinone}
CONFIG=${CONFIG:-$MODDIR/config}
STATE=${STATE:-$MODDIR/state}

lkm_present() {
    [ -e /proc/susfs_path ] || [ -d /sys/module/susfs_guard_lkm ] || [ -d /sys/module/susfs ]
}

find_ksu_bin_dir() {
    if [ -d /data/adb/ksu/bin ]; then
        echo /data/adb/ksu/bin
        return 0
    fi
    if [ -d /data/adb/ap/bin ]; then
        echo /data/adb/ap/bin
        return 0
    fi
    if [ -d /data/adb/ksu ]; then
        echo /data/adb/ksu/bin
        return 0
    fi
    if [ -d /data/adb/ap ]; then
        echo /data/adb/ap/bin
        return 0
    fi
    return 1
}

find_susfs_bin() {
    if [ -n "$SUSFS_BIN" ] && [ -x "$SUSFS_BIN" ]; then
        echo "$SUSFS_BIN"
        return 0
    fi
    for p in \
        /data/adb/ksu/bin/ksu_susfs \
        /data/adb/ap/bin/ksu_susfs \
        /data/adb/ksu/bin/susfs \
        /data/adb/ap/bin/susfs \
        /system/bin/ksu_susfs \
        /system/xbin/ksu_susfs; do
        [ -x "$p" ] && { echo "$p"; return 0; }
    done
    for p in /data/adb/modules/*/bin/ksu_susfs /data/adb/modules/*/system/bin/ksu_susfs; do
        [ -x "$p" ] && { echo "$p"; return 0; }
    done
    p=$(command -v ksu_susfs 2>/dev/null)
    [ -n "$p" ] && [ -x "$p" ] && { echo "$p"; return 0; }
    return 1
}

find_susfs_backup() {
    [ -x "$MODDIR/bin/ksu_susfs_good" ] && { echo "$MODDIR/bin/ksu_susfs_good"; return 0; }
    return 1
}

# 没有活动二进制时，把模块自带备份放进当前管理器的 bin 目录，兼容旧模块/其他工具。
ensure_susfs_bin() {
    _bin=$(find_susfs_bin)
    [ -n "$_bin" ] && { echo "$_bin"; return 0; }
    _backup=$(find_susfs_backup) || return 1
    _dir=$(find_ksu_bin_dir)
    if [ -n "$_dir" ]; then
        mkdir -p "$_dir" 2>/dev/null
        if cp -f "$_backup" "$_dir/ksu_susfs" 2>/dev/null && chmod 755 "$_dir/ksu_susfs" 2>/dev/null; then
            echo "$_dir/ksu_susfs"
            return 0
        fi
    fi
    echo "$_backup"
}

# 优先使用当前管理器自带的 ksu_susfs；它不能通信时回退到模块备份（不覆盖分支文件）。
select_susfs_bin() {
    _active=$(find_susfs_bin)
    _backup=$(find_susfs_backup)
    if lkm_present; then
        if [ -n "$_active" ] && "$_active" show version >/dev/null 2>&1; then
            echo "$_active"
            return 0
        fi
        if [ -n "$_backup" ] && "$_backup" show version >/dev/null 2>&1; then
            echo "$_backup"
            return 0
        fi
        [ -n "$_active" ] && { echo "$_active"; return 0; }
        [ -n "$_backup" ] && { echo "$_backup"; return 0; }
    else
        [ -n "$_active" ] && { echo "$_active"; return 0; }
        [ -n "$_backup" ] && { echo "$_backup"; return 0; }
    fi
    return 1
}

root_family() {
    if [ -d /data/adb/ksu ]; then
        echo "KernelSU"
    elif [ -d /data/adb/ap ]; then
        echo "APatch"
    elif [ -d /data/adb/magisk ]; then
        echo "Magisk"
    else
        echo "Unknown"
    fi
}

# 仅状态页调用；pm 在开机早期可能不可用，失败时回退到“KernelSU 系列”。
ksu_branch() {
    if [ -d /data/adb/ksu ]; then
        _pkgs=$(pm list packages 2>/dev/null)
        case "$_pkgs" in
            *com.sukisu.ultra*) echo "SukiSU"; return 0 ;;
            *com.resukisu*) echo "ReSukiSU"; return 0 ;;
            *com.rifsxd.ksunext*) echo "KernelSU Next"; return 0 ;;
            *me.weishu.kernelsu*) echo "KernelSU"; return 0 ;;
            *) echo "KernelSU 系列"; return 0 ;;
        esac
    fi
    if [ -d /data/adb/ap ]; then
        echo "APatch"
        return 0
    fi
    if [ -d /data/adb/magisk ]; then
        echo "Magisk"
        return 0
    fi
    echo "Unknown"
}

marker_paths() {
    echo /data/adb/ksu/susfs4ksu/logs/susfs_active
    echo /data/adb/ap/susfs4ksu/logs/susfs_active
    echo /data/adb/susfs4ksu/logs/susfs_active
}

marker_exists() {
    for _p in $(marker_paths); do
        [ -f "$_p" ] && return 0
    done
    return 1
}

touch_marker() {
    if [ -d /data/adb/ksu ]; then
        _marker=/data/adb/ksu/susfs4ksu/logs/susfs_active
    elif [ -d /data/adb/ap ]; then
        _marker=/data/adb/ap/susfs4ksu/logs/susfs_active
    else
        _marker=/data/adb/susfs4ksu/logs/susfs_active
    fi
    mkdir -p "${_marker%/*}" 2>/dev/null
    touch "$_marker" 2>/dev/null
}
