#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# 共享的 root 管理器与 ksu_susfs 路径检测。
# 兼容 KernelSU 官方版及 SukiSU / ReSukiSU / KernelSU Next 等分支，
# 也兼容 APatch 的二进制目录（模块安装仍以 KernelSU 系列为主）。

MODDIR=${MODDIR:-/data/adb/modules/susfs_allinone}
# CONFIG/STATE 只从 MODDIR 推导：不允许调用方用环境变量把它们指向模块外
CONFIG=$MODDIR/config
STATE=$MODDIR/state

lkm_present() {
    [ -e /proc/susfs_path ] || [ -d /sys/module/susfs_guard_lkm ] || [ -d /sys/module/susfs ]
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
    # 不向管理器目录（/data/adb/ksu/bin 等）写任何文件：
    # 找不到可用二进制时直接用模块自带的备份，由 select_susfs_bin 负责本次运行。
    _bin=$(find_susfs_bin)
    [ -n "$_bin" ] && { echo "$_bin"; return 0; }
    find_susfs_backup
}

# 优先使用当前管理器自带的 ksu_susfs；它不能通信时回退到模块备份（不覆盖分支文件）。
# 管理器自带的 ksu_susfs 是否能真正执行（区分「架构不符」与「通信失败」）
susfs_bin_runnable() {
    _b=$1
    [ -n "$_b" ] && [ -x "$_b" ] || return 1
    _o=$("$_b" show version 2>&1)
    [ -n "$_o" ] || return 1
    case "$_o" in
        *"Exec format error"*|*"cannot execute"*|*"not found"*) return 1 ;;
    esac
    return 0
}

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

# ---- 配置读取（config.ini，纯数据，不 source）----
# 配置不再是 shell 脚本：只按 KEY=VALUE 解析，值永远不会被执行。
CFG_KEYS="auto_load hide_sus_mnts avc_spoof replace_rules hide_ksu_loop hide_revanced hide_custom_rom hide_compat_matrix hide_gapps hide_dex2oat hide_scene auto_try_umount skip_legit_mounts skip_detection_paths fake_cmdline fake_cmdline_value force_kmi manager_name spoof_uname spoof_uname_release spoof_uname_version hide_vendor_sepolicy vold_isolation force_bl_unlocked"

# 读单个键（$1=键，$2=默认值）
cfg_get() {
    _k=$1; _d=${2:-}
    _f="$CONFIG/config.ini"
    [ -f "$_f" ] || { printf '%s' "$_d"; return 0; }
    _v=$(grep "^$_k=" "$_f" 2>/dev/null | tail -1 | cut -d= -f2-)
    if [ -n "$_v" ]; then printf '%s' "$_v"; else printf '%s' "$_d"; fi
}

# 一次性把已知键读成同名 shell 变量（显式 case，不用 eval）
cfg_load() {
    _f="$CONFIG/config.ini"
    [ -f "$_f" ] || return 0
    while IFS= read -r _line || [ -n "$_line" ]; do
        case "$_line" in
            ""|"#"*) continue ;;
        esac
        _k=${_line%%=*}
        _v=${_line#*=}
        case "$_k" in
            auto_load) auto_load=$_v ;;
            hide_sus_mnts) hide_sus_mnts=$_v ;;
            avc_spoof) avc_spoof=$_v ;;
            replace_rules) replace_rules=$_v ;;
            hide_ksu_loop) hide_ksu_loop=$_v ;;
            hide_revanced) hide_revanced=$_v ;;
            hide_custom_rom) hide_custom_rom=$_v ;;
            hide_compat_matrix) hide_compat_matrix=$_v ;;
            hide_gapps) hide_gapps=$_v ;;
            hide_dex2oat) hide_dex2oat=$_v ;;
            hide_scene) hide_scene=$_v ;;
            auto_try_umount) auto_try_umount=$_v ;;
            skip_legit_mounts) skip_legit_mounts=$_v ;;
            skip_detection_paths) skip_detection_paths=$_v ;;
            fake_cmdline) fake_cmdline=$_v ;;
            fake_cmdline_value) fake_cmdline_value=$_v ;;
            force_kmi) force_kmi=$_v ;;
            manager_name) manager_name=$_v ;;
            spoof_uname) spoof_uname=$_v ;;
            spoof_uname_release) spoof_uname_release=$_v ;;
            spoof_uname_version) spoof_uname_version=$_v ;;
            hide_vendor_sepolicy) hide_vendor_sepolicy=$_v ;;
            vold_isolation) vold_isolation=$_v ;;
            *) : ;;
        esac
    done < "$_f"
}

# 旧 config.sh → config.ini 迁移：只提取 KEY=VALUE 行，绝不 source
cfg_migrate() {
    [ -f "$CONFIG/config.ini" ] && return 0
    [ -f "$CONFIG/config.sh" ] || return 0
    _tmp="$CONFIG/config.ini.tmp"
    _dropped=0
    : > "$_tmp" 2>/dev/null || return 0
    while IFS= read -r _line || [ -n "$_line" ]; do
        case "$_line" in
            "") printf '\n' >> "$_tmp" ;;
            "#"*) printf '%s\n' "$_line" >> "$_tmp" ;;
            [A-Za-z_]*=*) printf '%s\n' "$_line" >> "$_tmp" ;;
            *) _dropped=$((_dropped + 1)) ;;
        esac
    done < "$CONFIG/config.sh"
    mv -f "$_tmp" "$CONFIG/config.ini" 2>/dev/null || return 0
    mv -f "$CONFIG/config.sh" "$CONFIG/config.sh.bak" 2>/dev/null
    echo "[i] 配置已迁移到 config.ini（旧文件保留为 config.sh.bak）"
    [ "$_dropped" -gt 0 ] && echo "[!] 迁移时丢弃 $_dropped 行非 KEY=VALUE 内容"
    return 0
}

# 确保配置存在：迁移旧文件，或从模板生成默认值
cfg_ensure() {
    cfg_migrate
    [ -f "$CONFIG/config.ini" ] && return 0
    [ -f "$CONFIG/config.ini.default" ] && cp -f "$CONFIG/config.ini.default" "$CONFIG/config.ini" 2>/dev/null
    return 0
}

# ---- BL 强制解锁标记（独立文件，通用配置写入器碰不到）----
bl_force_flag_path() { printf '%s' "$STATE/force_bl_unlocked"; }

cfg_force_bl() {
    _p=$(bl_force_flag_path)
    if [ -f "$_p" ]; then
        _v=$(cat "$_p" 2>/dev/null)
        case "$_v" in
            0|1) printf '%s' "$_v"; return 0 ;;
        esac
    fi
    # 一次性迁移：1.2.0 早期把该值写在 config.ini 里，迁到独立文件后立刻删除，
    # 避免通过通用配置写入器绕过确认
    _old=$(cfg_get force_bl_unlocked "")
    case "$_old" in
        0|1)
            set_force_bl "$_old"
            [ -f "$CONFIG/config.ini" ] && sed -i "/^force_bl_unlocked=/d" "$CONFIG/config.ini" 2>/dev/null
            printf '%s' "$_old"
            return 0
            ;;
    esac
    printf '0'
}

set_force_bl() {
    mkdir -p "$STATE" 2>/dev/null
    printf '%s\n' "$1" > "$(bl_force_flag_path)" 2>/dev/null
}

# 仅状态页调用；pm 在开机早期可能不可用，失败时回退到“KernelSU 系列”。
ksu_branch() {
    # 允许手动固定显示名（配置项 manager_name），用于包名相同无法区分的分支
    _mn=$(cfg_get manager_name)
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
    # 本模块自己的标记写在这里；旧版 susfs4ksu 的路径只作为兼容参考
    [ -f "$STATE/susfs_active" ] && return 0
    for _p in $(marker_paths); do
        [ -f "$_p" ] && return 0
    done
    return 1
}

touch_marker() {
    # 只在模块自己的 state 目录留标记，完全不触碰模块目录以外的路径
    mkdir -p "$STATE" 2>/dev/null
    : > "$STATE/susfs_active" 2>/dev/null
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

    # 特性位 vs 实际命令能力：特性位可能谎报（见上游 #122）
    _b=$(select_susfs_bin 2>/dev/null)
    if [ -n "$_b" ]; then
        _f=$("$_b" show enabled_features 2>/dev/null)
        echo "--- capabilities ---"
        case "$_f" in
            *CONFIG_KSU_SUSFS_SUS_MOUNT*) echo "feature_sus_mount=1" ;;
            *) echo "feature_sus_mount=0" ;;
        esac
        case "$_f" in
            *CONFIG_KSU_SUSFS_TRY_UMOUNT*) echo "feature_try_umount=1" ;;
            *) echo "feature_try_umount=0" ;;
        esac
        # 实测结果只从 caps 缓存读，不再调用会改状态的命令
        _caps="$STATE/$CAPS_FILE_NAME"
        _ps=$(grep '^sus_mount=' "$_caps" 2>/dev/null | tail -1 | cut -d= -f2)
        _pt=$(grep '^try_umount=' "$_caps" 2>/dev/null | tail -1 | cut -d= -f2)
        _pss=$(grep '^sus_mount_src=' "$_caps" 2>/dev/null | tail -1 | cut -d= -f2)
        _pts=$(grep '^try_umount_src=' "$_caps" 2>/dev/null | tail -1 | cut -d= -f2)
        echo "recorded_sus_mount=${_ps:-unknown} (src=${_pss:-none})"
        echo "recorded_try_umount=${_pt:-unknown} (src=${_pts:-none})"
        case "$_f:${_ps:-}" in
            *CONFIG_KSU_SUSFS_SUS_MOUNT*:0) echo "verdict_sus_mount=特性位声称支持，但实测失败（见 issue #5）" ;;
            *CONFIG_KSU_SUSFS_SUS_MOUNT*:1) echo "verdict_sus_mount=特性位声明支持，实测状态见 recorded" ;;
            *) echo "verdict_sus_mount=内核未声明该特性" ;;
        esac
        case "$_f:${_pt:-}" in
            *CONFIG_KSU_SUSFS_TRY_UMOUNT*:0) echo "verdict_try_umount=特性位声称支持，但实测失败（见 issue #5）" ;;
            *CONFIG_KSU_SUSFS_TRY_UMOUNT*:1) echo "verdict_try_umount=特性位声明支持，实测状态见 recorded" ;;
            *) echo "verdict_try_umount=内核未声明该特性" ;;
        esac
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
    # 伪回锁设备：属性被伪装成 locked，允许用户显式确认后覆盖
    [ "$(cfg_force_bl)" = "1" ] && return 0
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
# 真实系统分区（根挂载为 /）不应加入卸载列表
is_legit_partition_mount() {
    _fs=$1; _root=$2
    case "$_fs" in
        erofs|ext4|f2fs|squashfs|vfat)
            [ "$_root" = "/" ] && return 0 ;;
    esac
    return 1
}

# ---- 挂载规则去重 ----
# 内核侧没有查询接口，也无法判断是否幂等；这里按「本次开机」在模块侧记账，
# 避免同一路径反复下发导致内核列表膨胀（重启后内核列表已清空，记录随之失效）。
_mount_dedup_prepare() {
    # $1 = 记录文件路径
    _hf=$1
    _hb="$_hf.boot"
    _bid=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
    [ "$(cat "$_hb" 2>/dev/null)" = "$_bid" ] && return 0
    : > "$_hf" 2>/dev/null
    [ -n "$_bid" ] && echo "$_bid" > "$_hb" 2>/dev/null
    return 0
}

# 返回 0=本次已添加，2=之前已添加过（跳过），1=添加失败
sus_mount_add_once() {
    _p=$1
    _hf="$STATE/sus_mount_added.txt"
    _mount_dedup_prepare "$_hf"
    grep -Fqx -- "$_p" "$_hf" 2>/dev/null && return 2
    "$BIN" add_sus_mount "$_p" >/dev/null 2>&1 || return 1
    printf '%s\n' "$_p" >> "$_hf" 2>/dev/null
    return 0
}

try_umount_add_once() {
    _p=$1
    _hf="$STATE/try_umount_added.txt"
    _mount_dedup_prepare "$_hf"
    grep -Fqx -- "$_p" "$_hf" 2>/dev/null && return 2
    "$BIN" add_try_umount "$_p" 1 >/dev/null 2>&1 || return 1
    printf '%s\n' "$_p" >> "$_hf" 2>/dev/null
    return 0
}

# ---- 运行时锁与耗时判断 ----
# mkdir 是原子的：用它做简单互斥，避免开机 apply 与 WebUI apply 同时写规则
lock_acquire() {
    _lk=$1; _ttl=${2:-900}
    mkdir -p "$STATE" 2>/dev/null
    # 锁目录里记录持有者 PID：过期被接管后，旧持有者退出时不能删掉新锁
    mkdir "$_lk" 2>/dev/null && { echo $$ > "$_lk/pid" 2>/dev/null; return 0; }
    _now=$(date +%s 2>/dev/null)
    _mt=$(stat -c %Y "$_lk" 2>/dev/null)
    [ -n "$_now" ] && [ -n "$_mt" ] || return 1
    case "$_now$_mt" in *[!0-9]*) return 1 ;; esac
    if [ $((_now - _mt)) -gt "$_ttl" ]; then
        # 原子接管：只有成功把过期目录改名的那一方才能重建锁，
        # 否则两个进程同时判定过期会互删对方刚建的锁
        _stale="$STATE/.lock.stale.$$"
        if mv "$_lk" "$_stale" 2>/dev/null; then
            rm -rf "$_stale" 2>/dev/null
            mkdir "$_lk" 2>/dev/null && { echo $$ > "$_lk/pid" 2>/dev/null; return 0; }
        fi
    fi
    return 1
}

lock_release() {
    # 只释放自己持有的锁
    if [ -f "$1/pid" ] && [ "$(cat "$1/pid" 2>/dev/null)" != "$$" ]; then
        return 0
    fi
    rm -rf "$1" 2>/dev/null
}

# 文件是否早于 N 秒（不依赖 find -mmin，toybox 兼容性更稳）
file_older_than() {
    _now=$(date +%s 2>/dev/null)
    _mt=$(stat -c %Y "$1" 2>/dev/null)
    # stat 失败（文件不存在/不支持）不能当成"很旧"，否则会把缺失的锁当过期
    [ -n "$_now" ] && [ -n "$_mt" ] || return 1
    case "$_now$_mt" in *[!0-9]*) return 1 ;; esac
    [ $((_now - _mt)) -gt "$2" ]
}

# ---- 真实内核版本 ----
# 选 KMI 必须用真实内核：/proc/sys/kernel/osrelease 可能被本模块的 uname 伪装改写，
# 用被改写的值去匹配会在伪装开启时选错 .ko（例如 6.12 内核匹配成 android15-6.6）。
real_kernel_release() {
    _rk=""
    # 1) /proc/version 来自内核 banner，通常不受 utsname 伪装影响
    #    路径可覆盖，便于离线测试
    _pv=${PROC_VERSION_FILE:-/proc/version}
    if [ -r "$_pv" ]; then
        _rk=$(awk 'NR==1 { if ($3 ~ /^[0-9]+\.[0-9]+/ && $3 ~ /android[0-9]/) print $3 }' "$_pv" 2>/dev/null)
    fi
    # 2) 启动时落盘的真实内核快照
    if [ -z "$_rk" ] && [ -f "$STATE/real_uname.txt" ]; then
        _rk=$(grep '^release=' "$STATE/real_uname.txt" 2>/dev/null | head -1 | cut -d= -f2-)
    fi
    # 3) 最后才退回可能被伪装的 osrelease
    if [ -z "$_rk" ]; then
        _rk=$(cat /proc/sys/kernel/osrelease 2>/dev/null)
    fi
    printf '%s' "$_rk"
}

# ---- sus_path 规则的作用域管理 ----
# 目标：清理时只删除本模块写入的路径，不动其他隐藏模块的规则。
# 节点路径可覆盖，便于离线测试。
SUSFS_PATH_NODE=${SUSFS_PATH_NODE:-/proc/susfs_path}

our_paths_file() { printf '%s' "$STATE/our_paths.txt"; }

# 删除单条规则；返回非 0 表示节点不支持或该条不存在
susfs_path_del() {
    _p=$1
    [ -n "$_p" ] || return 1
    [ -e "$SUSFS_PATH_NODE" ] || return 1
    echo "del $_p" >> "$SUSFS_PATH_NODE" 2>/dev/null
}

# 记录本模块成功写入的路径（去重）
record_our_path() {
    _p=$1
    [ -n "$_p" ] || return 0
    _f=$(our_paths_file)
    mkdir -p "$STATE" 2>/dev/null
    grep -Fqx -- "$_p" "$_f" 2>/dev/null || printf '%s\n' "$_p" >> "$_f"
}

# replace_rules=1：只移除上一次记录的路径
clear_own_paths() {
    _f=$(our_paths_file)
    if [ ! -s "$_f" ]; then
        echo "[i] 无历史规则清单，跳过清理（不触碰其他模块的规则）"
        return 0
    fi
    _n=0; _fail=0
    _pending="$STATE/our_paths.pending.txt"
    : > "$_pending" 2>/dev/null
    while IFS= read -r _p || [ -n "$_p" ]; do
        [ -n "$_p" ] || continue
        if susfs_path_del "$_p"; then
            _n=$((_n + 1))
        else
            _fail=$((_fail + 1))
            printf '%s\n' "$_p" >> "$_pending" 2>/dev/null
        fi
    done < "$_f"
    # 删除失败的条目留在清单里，下次继续尝试，避免变成无法清理的孤儿规则
    if [ -s "$_pending" ]; then
        mv -f "$_pending" "$_f" 2>/dev/null
    else
        : > "$_f"
        rm -f "$_pending" 2>/dev/null
    fi
    echo "[i] 已移除本模块上次写入的规则: 成功 $_n 条，失败 $_fail 条"
    if [ "$_n" = "0" ] && [ "$_fail" -gt 0 ]; then
        echo "[!] 当前内核不支持 del，旧规则无法逐条移除；如需整表清空请显式设置 replace_rules=2"
    fi
}

# 首次迁移：旧版本用整表 clear 写入规则，没有留下清单。
# 以当前配置里声明的路径为候选逐条删除，只动配置内的路径。
clear_migrated_paths() {
    _cfg=$1
    [ -f "$_cfg" ] || return 0
    _n=0; _fail=0
    while IFS= read -r _line || [ -n "$_line" ]; do
        _p=$(printf '%s' "$_line" | tr -d '\r')
        _p=${_p%%#*}
        _p=$(printf '%s' "$_p" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -n "$_p" ] || continue
        case "$_p" in /*) ;; *) continue ;; esac
        if susfs_path_del "$_p"; then _n=$((_n + 1)); else _fail=$((_fail + 1)); fi
    done < "$_cfg"
    echo "[i] 首次迁移：按配置清理旧规则 成功 $_n 条，失败 $_fail 条"
    [ "$_n" = "0" ] && [ "$_fail" -gt 0 ] && echo "[!] 内核不支持 del，旧规则无法逐条移除"
    return 0
}

# 显式整表清空（replace_rules=2，会影响其他模块）
clear_all_paths() {
    [ -e "$SUSFS_PATH_NODE" ] || return 1
    echo clear >> "$SUSFS_PATH_NODE" 2>/dev/null || return 1
    : > "$(our_paths_file)"
}

# 当前 osrelease 与真实内核不一致 = uname 伪装正在生效
kernel_release_spoofed() {
    _os=$(cat /proc/sys/kernel/osrelease 2>/dev/null)
    _real=$(real_kernel_release)
    [ -n "$_os" ] && [ -n "$_real" ] && [ "$_os" != "$_real" ]
}
# ---- 配置自愈 ----
# 覆盖面被模块升级/合并冲掉的情况：apply 成功后备份 config，启动时若发现缺失则还原。
backup_config() {
    [ -d "$CONFIG" ] || return 0
    mkdir -p "$STATE/config_backup" 2>/dev/null || return 0
    for _f in config.ini sus_path.txt sus_mount.txt try_umount.txt hide_modules.txt skip_hide.txt; do
        [ -f "$CONFIG/$_f" ] && cp -f "$CONFIG/$_f" "$STATE/config_backup/$_f" 2>/dev/null
    done
    # 带时间戳的历史副本，保留最近 3 份（防止当前配置被默认值覆盖后备份也跟着丢）
    _stamp=$(date '+%Y%m%d-%H%M%S' 2>/dev/null)
    if [ -n "$_stamp" ] && [ -d "$STATE/config_backup" ]; then
        mkdir -p "$STATE/config_backup/history/$_stamp" 2>/dev/null
        for _f in config.ini sus_path.txt; do
            [ -f "$STATE/config_backup/$_f" ] && \
                cp -f "$STATE/config_backup/$_f" "$STATE/config_backup/history/$_stamp/$_f" 2>/dev/null
        done
        ls -1dt "$STATE/config_backup/history"/* 2>/dev/null | tail -n +4 | while read -r _old; do
            rm -rf "$_old" 2>/dev/null
        done
    fi
}

restore_config_if_missing() {
    [ -f "$CONFIG/config.ini" ] && return 0
    [ -f "$STATE/config_backup/config.ini" ] || return 0
    mkdir -p "$CONFIG" 2>/dev/null || return 0
    # 只补缺失的文件：已有的规则文件可能是更新的，不能被旧备份覆盖
    _restored=0
    for _f in config.ini config.ini.default sus_path.txt sus_mount.txt try_umount.txt hide_modules.txt skip_hide.txt; do
        [ -f "$CONFIG/$_f" ] && continue
        [ -f "$STATE/config_backup/$_f" ] || continue
        cp -f "$STATE/config_backup/$_f" "$CONFIG/$_f" 2>/dev/null && _restored=$((_restored + 1))
    done
    [ "$_restored" -gt 0 ] && echo "[i] 检测到配置缺失，已从备份还原 $_restored 个文件"
}
# ---- 运行时能力探测 ----
# 特性位可能谎报（上游 #122 修复前），所以直接拿命令试一次。
# 结果缓存到 state/caps：<name>=1|0
CAPS_FILE_NAME="caps"

# 判定内核是否声明了某个 SUSFS 特性（不调用会改状态的命令）
susfs_feature_enabled() {
    _feat=$1
    [ -n "$_feat" ] || return 1
    _b=$(select_susfs_bin 2>/dev/null) || return 1
    "$_b" show enabled_features 2>/dev/null | grep -qx "$_feat"
}

# 记录一次实测失败：把该能力标记为不可用，避免重复尝试
caps_downgrade() {
    _name=$1
    _f="$STATE/$CAPS_FILE_NAME"
    [ -f "$_f" ] || caps_refresh
    [ -f "$_f" ] || return 0
    # 用 awk 重写，避免依赖 sed -i（部分机型/toybox 行为不一致）
    awk -v n="$_name" '
        BEGIN { done = 0; src = 0 }
        $0 ~ "^" n "=" { print n "=0"; done = 1; next }
        $0 ~ "^" n "_src=" { print n "_src=probe"; src = 1; next }
        { print }
        END { if (!done) print n "=0"; if (!src) print n "_src=probe" }
    ' "$_f" > "$_f.tmp" 2>/dev/null && mv -f "$_f.tmp" "$_f" 2>/dev/null
}

caps_refresh() {
    mkdir -p "$STATE" 2>/dev/null
    _f="$STATE/$CAPS_FILE_NAME"
    # 只读判定：特性位可能谎报（上游 #122），实测失败时由 caps_downgrade 降级为 0
    {
        if susfs_feature_enabled CONFIG_KSU_SUSFS_SUS_MOUNT; then echo "sus_mount=1"; else echo "sus_mount=0"; fi
        echo "sus_mount_src=feature"
        if susfs_feature_enabled CONFIG_KSU_SUSFS_TRY_UMOUNT; then echo "try_umount=1"; else echo "try_umount=0"; fi
        echo "try_umount_src=feature"
        echo "lkm=$([ -d /sys/module/susfs_guard_lkm ] && echo 1 || echo 0)"
        echo "boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
        echo "checked_at=$(date '+%F %T' 2>/dev/null)"
    } > "$_f" 2>/dev/null
}

cap_ok() {
    _f="$STATE/$CAPS_FILE_NAME"
    _bid=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
    _cached=$(grep '^boot_id=' "$_f" 2>/dev/null | tail -1 | cut -d= -f2-)
    # LKM 装载状态也要参与判定：未加载时判定出的 0 不能留到加载之后
    _lk=$([ -d /sys/module/susfs_guard_lkm ] && echo 1 || echo 0)
    _cached_lk=$(grep '^lkm=' "$_f" 2>/dev/null | tail -1 | cut -d= -f2-)
    if [ ! -f "$_f" ] || { [ -n "$_bid" ] && [ "$_bid" != "$_cached" ]; } || [ "$_lk" != "$_cached_lk" ]; then
        caps_refresh
    fi
    [ "$(grep "^$1=" "$_f" 2>/dev/null | tail -1 | cut -d= -f2)" = "1" ]
}
# ---- 诊断：ksu_susfs 通信失败排查 ----
# 输出两个二进制对同一内核的响应，便于判断是二进制 ABI 不匹配还是 LKM 问题。
diag_tooling() {
    echo "osrelease=$(cat /proc/sys/kernel/osrelease 2>/dev/null)"
    . "$MODDIR/kmi.sh" 2>/dev/null
    echo "kmi=$(select_kmi "$(cat /proc/sys/kernel/osrelease 2>/dev/null)" "$MODDIR" 2>/dev/null)"
    if lkm_present; then echo "lkm_present=1"; else echo "lkm_present=0"; fi
    echo "proc_nodes=$(ls /proc/susfs_* 2>/dev/null | tr '\n' ' ')"
    if [ -d /sys/module/susfs_guard_lkm ]; then echo "module_sysfs=susfs_guard_lkm"; else echo "module_sysfs=none"; fi
    echo "module_in_proc_modules=$(grep -ic susfs /proc/modules 2>/dev/null)"

    for _b in /data/adb/ksu/bin/ksu_susfs /data/adb/ap/bin/ksu_susfs "$MODDIR/bin/ksu_susfs_good"; do
        [ -x "$_b" ] || continue
        echo "--- $_b ---"
        _o=$("$_b" show version 2>&1); echo "show_version_rc=$? out=$_o"
        _o=$("$_b" show variant 2>&1); echo "show_variant_rc=$? out=$_o"
        _o=$("$_b" show enabled_features 2>&1 | head -3 | tr '\n' ' '); echo "features_head=$_o"
    done

    echo "--- dmesg ---"
    dmesg 2>/dev/null | grep -iE "susfs|supercall" | tail -8
}
# 读取 ELF 架构（判断 ksu_susfs 是否与本机匹配）
# 返回 aarch64 / x86_64 / arm / x86 / not-elf / missing / machine=N
elf_machine() {
    _f=$1
    [ -f "$_f" ] || { echo "missing"; return 0; }
    _magic=$(od -An -tx1 -N4 "$_f" 2>/dev/null | tr -d " \n")
    [ "$_magic" = "7f454c46" ] || { echo "not-elf"; return 0; }
    _lo=$(od -An -tu1 -j18 -N1 "$_f" 2>/dev/null | tr -d " ")
    _hi=$(od -An -tu1 -j19 -N1 "$_f" 2>/dev/null | tr -d " ")
    _m=$(( ${_hi:-0} * 256 + ${_lo:-0} ))
    case "$_m" in
        183) echo "aarch64" ;;
        62)  echo "x86_64" ;;
        40)  echo "arm" ;;
        3)   echo "x86" ;;
        *)   echo "machine=$_m" ;;
    esac
}
# 判断是否为「检测类应用自身的数据目录」：隐藏它们会让检测工具行为异常，
# 反而更容易被判为异常环境，因此默认跳过。
# 若 skip_hide.txt 缺失（例如升级时配置目录被跳过），按默认列表生成一份
ensure_skip_hide_file() {
    _f="$CONFIG/skip_hide.txt"
    [ -f "$_f" ] && return 0
    mkdir -p "$CONFIG" 2>/dev/null
    {
        echo "# 不隐藏的包名/路径片段，每行一个（子串匹配，支持 # 注释）"
        echo "# 隐藏检测类应用自己的数据目录会让它判定异常，需要时把包名加到这里"
        echo "duckdetector"
        echo "appvisibility"
        echo "nativecheck"
    } > "$_f" 2>/dev/null && echo "[i] 已生成默认 config/skip_hide.txt"
}

# 需要跳过隐藏的包名从 config/skip_hide.txt 读取（每行一个子串，支持 # 注释）
is_detection_app_path() {
    _p=$1
    [ -n "$_p" ] || return 1
    _f="$CONFIG/skip_hide.txt"
    [ -f "$_f" ] || return 1
    while IFS= read -r _pat || [ -n "$_pat" ]; do
        _pat=$(printf '%s' "$_pat" | tr -d '\r')
        _pat=${_pat%%#*}
        _pat=$(printf '%s' "$_pat" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -n "$_pat" ] || continue
        case "$_p" in *"$_pat"*) return 0 ;; esac
    done < "$_f"
    return 1
}
# ---- 兼容性检查 ----
# 检测环境里是否还有其他隐藏类模块，以及我们哪些开关可能与之互相影响。
compat_check() {
    echo "--- 环境 ---"
    echo "osrelease=$(cat /proc/sys/kernel/osrelease 2>/dev/null)"
    echo "modules_present=$(ls /data/adb/modules 2>/dev/null | tr '\n' ' ')"

    echo
    echo "--- 其他隐藏类模块 ---"
    _found=0
    for _m in /data/adb/modules/*/; do
        [ -d "$_m" ] || continue
        _id=$(basename "$_m")
        [ "$_id" = "susfs_allinone" ] && continue
        case "$_id" in
            *[_Hh][Aa][Mm][Aa]*|*hma*|*YH*|*yhyc*|*hide*|*Hide*|*shamiko*|*Shamiko*|*lsposed*|*LSPosed*)
                _found=$((_found + 1))
                echo "  发现: $_id"
                ;;
        esac
    done
    [ "$_found" = "0" ] && echo "  未发现其他隐藏类模块"

    echo
    echo "--- 我们的相关开关 ---"
    cfg_load
    echo "replace_rules=${replace_rules:-0}      # 1 = 只清理本模块写入的路径；2 = 整表清空（会影响别的模块）"
    echo "auto_try_umount=${auto_try_umount:-0}       # 自动把模块挂载加入卸载列表"

    echo
    echo "--- 建议 ---"
    [ "${replace_rules:-0}" = "2" ] && echo "  · replace_rules=2：会清空其他模块写入的 sus_path，除非确有需要建议改 0"
    [ "${auto_try_umount:-0}" = "1" ] && [ "$_found" -gt 0 ] && echo "  · 存在其他隐藏模块时，auto_try_umount 建议关掉再排查"
    echo "  · 出现异常时的最快排查：replace_rules=0、auto_try_umount=0"
}