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
    # 允许手动固定显示名（配置项 manager_name），用于包名相同无法区分的分支
    _mn=$(grep -s "^manager_name=" "$CONFIG/config.sh" 2>/dev/null | tail -1 | cut -d= -f2-)
    [ -n "$_mn" ] && { echo "$_mn"; return 0; }

    if [ -d /data/adb/ksu ]; then
        _pkgs=$(pm list packages 2>/dev/null)
        case "$_pkgs" in
            *com.sukisu.ultra*) echo "SukiSU"; return 0 ;;
            # BakaSU 沿用 ReSukiSU 的包名（com.resukisu.resukisu），仅凭包名无法区分
            *org.bakasu*) echo "BakaSU"; return 0 ;;
            *com.resukisu*) echo "ReSukiSU / BakaSU"; return 0 ;;
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

# 把 config/hide_modules.txt 里的模块名写回内核隐藏列表。
# LKM 每次重新加载都会清空内核侧列表，所以 load 之后要重新下发一次。
apply_hide_modules() {
    _hf="$CONFIG/hide_modules.txt"
    [ -f "$_hf" ] || return 0
    [ -e /proc/susfs_hide_modules ] || return 0
    while IFS= read -r _name || [ -n "$_name" ]; do
        _name=$(printf '%s' "$_name" | tr -d '\r')
        [ -n "$_name" ] || continue
        case "$_name" in '#'*) continue ;; esac
        if grep -qw "$_name" /proc/susfs_hide_modules 2>/dev/null; then
            echo "[=] hide_module $_name (已隐藏)"
            continue
        fi
        echo "add $_name" > /proc/susfs_hide_modules 2>/dev/null \
            && echo "[+] hide_module $_name" || echo "[=] hide_module $_name (失败)"
    done < "$_hf"
}

# 输出内核诊断信息（供 WebUI 与命令行排查用）
kmiinfo() {
    _rel=$(cat /proc/sys/kernel/osrelease 2>/dev/null)
    echo "osrelease=$_rel"
    echo "proc_version=$(cat /proc/version 2>/dev/null)"
    . "$MODDIR/kmi.sh" 2>/dev/null
    echo "matched=$(select_kmi "$_rel" "$MODDIR" 2>/dev/null)"
    echo "packaged=$(list_kmis "$MODDIR" | tr '
' ' ')"
    echo "guessed=$(guess_kmis "$_rel" "$MODDIR" | tr '
' ' ')"
    if [ -r /proc/config.gz ]; then
        zcat /proc/config.gz 2>/dev/null | grep -E "^CONFIG_LOCALVERSION=|^CONFIG_MODVERSIONS=|^CONFIG_CFI_CLANG=" | sed "s/^/cfg_/"
    else
        echo "cfg_unavailable=/proc/config.gz 不存在"
    fi
}

# 伪装 uname 之前把真实内核信息落盘，供出错后还原与排查。
# 只在文件不存在时写入：冷启动后第一次调用拿到的必然是真实值。
save_real_uname() {
    _f="$STATE/real_uname.txt"
    # 不带 force 时只在首次记录；带 force 用于「确认未伪装」时刷新（内核升级后自愈）
    [ -f "$_f" ] && [ "$1" != "force" ] && return 0
    _r=$(uname -r 2>/dev/null)
    [ -n "$_r" ] || return 0
    _v=$(uname -v 2>/dev/null)
    mkdir -p "$STATE" 2>/dev/null
    {
        echo "# 真实内核信息（伪装生效前记录）"
        echo "release=$_r"
        echo "version=$_v"
        echo "saved_at=$(date '+%F %T' 2>/dev/null)"
    } > "$_f" 2>/dev/null && echo "[i] 已记录真实内核: $_r"
}

# 用记录的真实值还原 uname（伪装出问题时手动救命用）
restore_real_uname() {
    _f="$STATE/real_uname.txt"
    if [ ! -f "$_f" ]; then
        echo "[!] 没有 real_uname.txt，无法还原"
        return 1
    fi
    _r=$(grep '^release=' "$_f" | head -1 | cut -d= -f2-)
    _v=$(grep '^version=' "$_f" | head -1 | cut -d= -f2-)
    [ -n "$_r" ] || { echo "[!] 记录里没有 release"; return 1; }
    _b=$(select_susfs_bin) || return 1
    if "$_b" set_uname "$_r" "${_v:-default}" >/dev/null 2>&1; then
        echo "[i] 已还原为: $_r"
        return 0
    fi
    echo "[!] 还原失败"
    return 1
}
# ---- 启动守卫：防止错误 .ko 造成开机循环 ----
# 自动加载前先落标记；只有真正开机完成（boot-completed）才会清除该标记。
# 若上次加载后设备没能完成启动（panic/卡死），下次开机会发现标记仍在，
# 自动停止加载并等待用户确认，避免无限重启。

boot_guard_path() {
    echo "$STATE/boot_guard"
}

autoload_paused() {
    [ -f "$STATE/autoload_paused" ]
}

mark_boot_guard() {
    mkdir -p "$STATE" 2>/dev/null
    {
        echo "kmi=${1:-unknown}"
        echo "at=$(date '+%F %T' 2>/dev/null)"
    } > "$(boot_guard_path)" 2>/dev/null
}

clear_boot_guard() {
    rm -f "$(boot_guard_path)" "$STATE/autoload_paused" 2>/dev/null
}

# 自动加载前的检查：返回 0 表示可以继续，1 表示应暂停自动加载
boot_guard_should_pause() {
    [ -f "$(boot_guard_path)" ] || return 0
    mkdir -p "$STATE" 2>/dev/null
    date '+%F %T' > "$STATE/autoload_paused" 2>/dev/null
    echo "[!] 检测到上次加载后未能完成启动，已暂停自动加载"
    echo "[!] 确认内核可用后在 WebUI 点「恢复自动加载」，或执行 ctl.sh resume_autoload"
    return 1
}

pause_autoload() {
    mkdir -p "$STATE" 2>/dev/null
    date '+%F %T' > "$STATE/autoload_paused" 2>/dev/null
}

resume_autoload() {
    clear_boot_guard
    rm -f "$STATE/fail_count" 2>/dev/null
    echo "[i] 已恢复自动加载（守卫标记已清除）"
}
# ---- 引导加载器（BL）锁状态检测 ----
# 未解锁：临时 root 场景，模块在 late-load 之后才运行，早期阶段功能不可靠
# 已解锁：永久 root，模块可在 post-fs-data 早期运行，可开放更多隐藏项
bootloader_state() {
    _vb=$(getprop ro.boot.verifiedbootstate 2>/dev/null)
    _lock=$(getprop ro.boot.flash.locked 2>/dev/null)
    _sb=$(getprop ro.secureboot.lockstate 2>/dev/null)
    case "$_vb" in
        orange|yellow) echo unlocked; return 0 ;;
    esac
    case "$_lock" in
        0) echo unlocked; return 0 ;;
        1) echo locked; return 0 ;;
    esac
    case "$_sb" in
        unlocked) echo unlocked; return 0 ;;
        locked) echo locked; return 0 ;;
    esac
    echo unknown
}

bl_unlocked() {
    [ "$(bootloader_state)" = "unlocked" ]
}

# 开机脚本统一门禁：返回 0 表示应继续执行
boot_gate_ok() {
    [ -f "$MODDIR/disable" ] && return 1
    [ -f "$MODDIR/remove" ] && return 1
    [ -f "$MODDIR/disable_autoload" ] && return 1
    [ "$(getprop persist.sys.safemode)" = "1" ] && return 1
    [ "$(getprop ro.sys.safemode)" = "1" ] && return 1
    return 0
}
