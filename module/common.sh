#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# 共享的 root 管理器与 ksu_susfs 路径检测。
# 兼容 KernelSU 官方版及 SukiSU / ReSukiSU / KernelSU Next 等分支，
# 也兼容 APatch 的二进制目录（模块安装仍以 KernelSU 系列为主）。

MODDIR=${MODDIR:-/data/adb/modules/susfs_allinone}
# CONFIG/STATE 只从 MODDIR 推导：不允许调用方用环境变量把它们指向模块外
CONFIG=$MODDIR/config
STATE=$MODDIR/state
_CF="$MODDIR/.cache.files"; _CFS="$STATE/.cache.idx"

lkm_present() {
    [ -e /proc/susfs_path ] || [ -d /sys/module/susfs_guard_lkm ] || [ -d /sys/module/susfs ]
}

# 内核侧 SUSFS 是否就绪：
#   lkm     —— 我们加载的 susfs_guard_lkm（有 /proc 或 sysfs 标记）
#   builtin —— 内核直接编入了 SUSFS（没有 LKM 标记，但 ksu_susfs 握手成功）
#   none    —— 两者都没有
# 结果缓存到 _SUSFS_KIND，避免重复执行二进制。
_susfs_detect() {
    [ -n "${_SUSFS_KIND:-}" ] && return 0
    if lkm_present; then
        _SUSFS_KIND=lkm
        return 0
    fi
    _sd_proc_dir=/proc
    [ "${SUSFS_TEST_HOOK:-0}" = "1" ] && [ -n "${SUSFS_PROC_DIR:-}" ] && _sd_proc_dir="$SUSFS_PROC_DIR"
    for _sd_b in "$(find_susfs_bin 2>/dev/null)" "$(find_susfs_backup 2>/dev/null)"; do
        [ -n "$_sd_b" ] && [ -x "$_sd_b" ] || continue
        # 仅"show version 成功"不足以证明是可用后端：要求有版本/特性输出，且内核确实暴露了接口节点
        "$_sd_b" show version >/dev/null 2>&1 || continue
        _sd_v=$("$_sd_b" show variant 2>/dev/null)
        _sd_f=$("$_sd_b" show enabled_features 2>/dev/null)
        [ -n "$_sd_v" ] || [ -n "$_sd_f" ] || continue
        _sd_node=0
        for _sd_p in "$_sd_proc_dir/susfs_path" "$_sd_proc_dir/susfs_hide_mounts" "$_sd_proc_dir/susfs_map" "$_sd_proc_dir/susfs_avc_spoof"; do
            [ -e "$_sd_p" ] && { _sd_node=1; break; }
        done
        [ "$_sd_node" = "1" ] || continue
        _SUSFS_KIND=builtin
        return 0
    done
    _SUSFS_KIND=none
}

susfs_kernel_kind() {
    _susfs_detect
    printf '%s' "$_SUSFS_KIND"
}

susfs_kernel_ready() {
    _susfs_detect
    [ "$_SUSFS_KIND" != "none" ]
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
    _susfs_detect
    if [ "$_SUSFS_KIND" != "none" ]; then
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
    # 目录可能残留（换过管理器），优先用运行时证据：Magisk 的 magiskd 常驻进程
    if command -v pidof >/dev/null 2>&1; then
        pidof magiskd >/dev/null 2>&1 && { echo "Magisk"; return 0; }
        pidof apd >/dev/null 2>&1 && { echo "APatch"; return 0; }
    fi
    if [ -d /data/adb/ksu ]; then
        echo "KernelSU"
    elif [ -d /data/adb/magisk ]; then
        echo "Magisk"
    elif [ -x /data/adb/ap/bin/apd ] || [ -x /data/adb/apd ]; then
        echo "APatch"
    else
        echo "Unknown"
    fi
}

# KernelPatch/APatch 内核存在时，kpimg 已经接管 SELinux 审计/策略面
# （avc_denied、slow_avc_audit、selinux_hide 等）。本模块与之语义重叠的功能
# 在共存时关闭，避免两边互相抵消。
#
# 判定只用强特征：残留的 /data/adb/ap 目录在换过管理器的设备上很常见，不能单独作为依据。
kernelpatch_present() {
    _kp_dir=/data/adb/ap
    [ "${SUSFS_TEST_HOOK:-0}" = "1" ] && _kp_dir="${KERNELPATCH_MARKER_DIR:-/data/adb/ap}"
    if command -v pidof >/dev/null 2>&1; then
        pidof apd >/dev/null 2>&1 && return 0
    fi
    [ -x /data/adb/apd ] && return 0
    [ -x "$_kp_dir/bin/apd" ] && return 0
    # package_config 只是数据文件；换过管理器的设备可能残留，不能单独作为依据。
    return 1
}

# KernelPatch kernel runtime probe: read the kpimg boot banner from dmesg
# ("KernelPatch Version: d09"). The userspace marker only proves APatch exists,
# not that kpimg is injected; unreadable dmesg returns unknown (not 0/1).
kernelpatch_kernel_probe() {
    # 同一进程内缓存（status 会同时取 state 和 version）；跨进程用 boot_id 缓存文件，
    # 避免每次刷新 WebUI 都完整读一遍 dmesg。
    _kp_cache_dir=$STATE
    [ -n "$_kp_cache_dir" ] || _kp_cache_dir=$MODDIR/state
    _kp_cache=$_kp_cache_dir/kp_probe
    if [ "${SUSFS_TEST_HOOK:-0}" = "1" ] || [ -n "${KERNELPATCH_DMESG_FILE:-}" ]; then
        # 测试钩子每轮都重新读文件，不能被上一轮进程缓存/文件缓存挡住
        _kp_cache=""
        _KP_PROBE_DONE=0
    fi
    _kp_boot_file=${PROC_BOOT_ID_FILE:-}
    [ -n "$_kp_boot_file" ] || _kp_boot_file=/proc/sys/kernel/random/boot_id
    _kp_boot=$(cat "$_kp_boot_file" 2>/dev/null)
    if [ -n "$_kp_cache" ] && [ -n "$_kp_boot" ] && [ -r "$_kp_cache" ]; then
        _kp_cb=$(sed -n 's/^boot_id=//p' "$_kp_cache" 2>/dev/null)
        if [ "$_kp_cb" = "$_kp_boot" ]; then
            _kp_st=$(sed -n 's/^state=//p' "$_kp_cache" 2>/dev/null)
            _kp_ver=$(sed -n 's/^version=//p' "$_kp_cache" 2>/dev/null)
            _KP_PROBE_DONE=1; _KP_PROBE_STATE=$_kp_st; _KP_PROBE_VER=$_kp_ver
            [ -n "$_kp_ver" ] && printf '%s\n' "$_kp_ver"
            case "$_kp_st" in 1) return 0 ;; 0) return 1 ;; *) return 2 ;; esac
        fi
    fi
    if [ "${_KP_PROBE_DONE:-0}" = "1" ]; then
        [ -n "$_KP_PROBE_VER" ] && printf '%s\n' "$_KP_PROBE_VER"
        case "$_KP_PROBE_STATE" in 1) return 0 ;; 0) return 1 ;; *) return 2 ;; esac
    fi
    _kp_ok=0
    if [ "${SUSFS_TEST_HOOK:-0}" = "1" ] && [ -n "${KERNELPATCH_DMESG_FILE:-}" ]; then
        if [ -r "$KERNELPATCH_DMESG_FILE" ] && _kp_log=$(cat "$KERNELPATCH_DMESG_FILE" 2>/dev/null); then
            _kp_ok=1
        fi
    elif _kp_log=$(dmesg 2>/dev/null); then
        _kp_ok=1
    fi
    _kp_st=unknown; _kp_ver=""
    if [ "$_kp_ok" = "1" ]; then
        if printf '%s\n' "$_kp_log" | grep -q 'KernelPatch'; then
            _kp_st=1
            _kp_ver=$(printf '%s\n' "$_kp_log" | sed -n 's/.*KernelPatch Version: *\([0-9A-Fa-fx._-]*\).*/\1/p' | head -1)
        else
            _kp_st=0
        fi
    fi
    _KP_PROBE_DONE=1; _KP_PROBE_STATE=$_kp_st; _KP_PROBE_VER=$_kp_ver
    if [ -n "$_kp_cache" ]; then
        mkdir -p "$_kp_cache_dir" 2>/dev/null
        { printf 'boot_id=%s\n' "$_kp_boot"; printf 'state=%s\n' "$_kp_st"; printf 'version=%s\n' "$_kp_ver"; } > "$_kp_cache" 2>/dev/null
    fi
    [ -n "$_kp_ver" ] && printf '%s\n' "$_kp_ver"
    case "$_kp_st" in 1) return 0 ;; 0) return 1 ;; *) return 2 ;; esac
}

kernelpatch_kernel_state() {
    # 直接调用而不是 $(...)，避免测试钩子变量/缓存状态丢在子 shell 里
    kernelpatch_kernel_probe >/dev/null
    _kp_rc=$?
    case "$_kp_rc" in
        0) echo 1 ;;
        1) echo 0 ;;
        *) echo unknown ;;
    esac
}

kernelpatch_kernel_version() {
    kernelpatch_kernel_probe >/dev/null || true
    [ -n "${_KP_PROBE_VER:-}" ] && printf '%s\n' "$_KP_PROBE_VER"
}

# 共存模式下禁用的功能：avc_spoof（与 kpimg 的 SELinux hook 重叠）
coexist_disable_avc_spoof() {
    kernelpatch_present
}

# APatch/KernelPatch 共存时是否允许外挂 SUSFS LKM（默认不允许，需显式放行）
apatch_lkm_allowed() {
    [ -f "$CONFIG/allow_lkm_on_kernelpatch" ] && return 0
    return 1
}

# pstore/ramoops 目录（测试钩子只在 SUSFS_TEST_HOOK=1 时生效）
_pstore_dir() {
    if [ "${SUSFS_TEST_HOOK:-0}" = "1" ]; then
        printf '%s' "${PSTORE_DIR:-/sys/fs/pstore}"
    else
        printf '%s' /sys/fs/pstore
    fi
}

# pstore 内容指纹：文件名 + 大小 + mtime；用于"已确认"后避免重复告警
_pstore_fingerprint() {
    _pf_dir=$(_pstore_dir)
    [ -d "$_pf_dir" ] || return 1
    {
        for _pf in "$_pf_dir"/*; do
            [ -f "$_pf" ] || continue
            printf '%s %s %s
' "$_pf" "$(stat -c %s "$_pf" 2>/dev/null)" "$(stat -c %Y "$_pf" 2>/dev/null)"
        done
    } | sha256sum 2>/dev/null | cut -d' ' -f1
}

# 用户已确认当前 pstore 记录（resume_autoload / ctl crash_ack 调用）
pstore_crash_ack() {
    _pa_fp=$(_pstore_fingerprint 2>/dev/null)
    [ -n "$_pa_fp" ] || return 1
    mkdir -p "$STATE" 2>/dev/null
    printf '%s
' "$_pa_fp" > "$STATE/crash_ack" 2>/dev/null
}

# 上次启动是否疑似因本模块崩溃：同一 pstore 文件里同时有 panic/oops 与模块栈字样
pstore_crash_suspect() {
    _pc_dir=$(_pstore_dir)
    [ -d "$_pc_dir" ] || return 1
    _pc_fp=$(_pstore_fingerprint 2>/dev/null)
    if [ -n "$_pc_fp" ] && [ "$(cat "$STATE/crash_ack" 2>/dev/null)" = "$_pc_fp" ]; then
        return 1
    fi
    for _pc_f in "$_pc_dir"/*; do
        [ -f "$_pc_f" ] || continue
        grep -qiE "Kernel panic|Oops|Unable to handle kernel|BUG:|Internal error" "$_pc_f" 2>/dev/null || continue
        grep -q "susfs_guard_lkm" "$_pc_f" 2>/dev/null && return 0
        grep -q "susfs_allinone" "$_pc_f" 2>/dev/null && return 0
    done
    return 1
}

# 读取内核配置项（/proc/config.gz；测试钩子 CONFIG_GZ_FILE 只在 SUSFS_TEST_HOOK=1 时生效）
# 用法: kernel_config_get CONFIG_KSU  ->  y / n / 空（未知）
kernel_config_get() {
    _kc_key=$1
    [ -n "$_kc_key" ] || return 1
    if [ -z "${_KC_FILE+x}" ]; then
        _kc_src=/proc/config.gz
        if [ "${SUSFS_TEST_HOOK:-0}" = "1" ] && [ -n "${CONFIG_GZ_FILE:-}" ]; then
            _kc_src="$CONFIG_GZ_FILE"
        fi
        _KC_FILE=""
        if [ -r "$_kc_src" ] && command -v zcat >/dev/null 2>&1; then
            mkdir -p "$STATE" 2>/dev/null
            _kc_tmp="$STATE/.kernel_config.$$"
            if zcat "$_kc_src" > "$_kc_tmp" 2>/dev/null && [ -s "$_kc_tmp" ]; then
                mv -f "$_kc_tmp" "$STATE/.kernel_config" 2>/dev/null
                _KC_FILE="$STATE/.kernel_config"
            else
                rm -f "$_kc_tmp" 2>/dev/null
            fi
        fi
    fi
    # 三态：读不到配置 -> unknown；能读到但没这个键 -> absent；显式 not set -> n
    [ -n "$_KC_FILE" ] && [ -r "$_KC_FILE" ] || { printf 'unknown'; return 0; }
    _kc_hit=$(grep -E "^$_kc_key=" "$_KC_FILE" 2>/dev/null | tail -1)
    if [ -n "$_kc_hit" ]; then
        printf '%s' "${_kc_hit#*=}"
        return 0
    fi
    if grep -qE "^# $_kc_key is not set$" "$_KC_FILE" 2>/dev/null; then
        printf 'n'
        return 0
    fi
    if grep -qE "^# $_kc_key" "$_KC_FILE" 2>/dev/null; then
        printf 'n'
        return 0
    fi
    printf 'absent'
    return 0
}

# insmod 前的内核限制预检：返回 0=可继续；否则把原因打到 stdout
kernel_load_preflight() {
    _klp_msd_file=/proc/sys/kernel/modules_disabled
    _klp_gz=/proc/config.gz
    if [ "${SUSFS_TEST_HOOK:-0}" = "1" ]; then
        [ -n "${MODULES_DISABLED_FILE:-}" ] && _klp_msd_file="$MODULES_DISABLED_FILE"
        [ -n "${CONFIG_GZ_FILE:-}" ] && _klp_gz="$CONFIG_GZ_FILE"
    fi
    _klp_msd=$(cat "$_klp_msd_file" 2>/dev/null)
    if [ "$_klp_msd" = "1" ]; then
        printf '%s' "内核已禁止模块加载（modules_disabled=1），请使用内置 SUSFS 的内核"
        return 1
    fi
    if [ -r "$_klp_gz" ] && command -v zcat >/dev/null 2>&1; then
        _klp_cfg=$(zcat "$_klp_gz" 2>/dev/null)
        if [ -n "$_klp_cfg" ]; then
            case "$_klp_cfg" in
                *CONFIG_MODULES=y*) : ;;
                *) printf '%s' "内核未编译 CONFIG_MODULES，无法加载 SUSFS LKM"; return 1 ;;
            esac
            case "$_klp_cfg" in
                *CONFIG_MODULE_SIG_FORCE=y*) printf '%s' "内核强制模块签名（MODULE_SIG_FORCE），SUSFS LKM 会加载失败"; return 1 ;;
            esac
        fi
    fi
    return 0
}

# APatch 的 SUSFS 依赖内核侧支持，失败原因与 KSU / Magisk 不同：描述里直接写清楚
susfs_hint() {
    case "$(root_family)" in
        APatch)
            case "$1" in
                missing) printf '%s' "APatch: 未找到 SUSFS 接口（内核需集成 SUSFS 或允许加载 SUSFS LKM）" ;;
                comm) printf '%s' "APatch: SUSFS 接口无响应（内核 SUSFS 版本可能不匹配）" ;;
                insmod) printf '%s' "APatch: LKM 加载失败（内核可能禁止 insmod 或符号不匹配）" ;;
                *) printf '%s' "APatch: SUSFS 不可用" ;;
            esac
            ;;
        *)
            case "$1" in
                missing) printf '%s' "ksu_susfs 缺失" ;;
                comm) printf '%s' "ksu_susfs 无法通信" ;;
                insmod) printf '%s' "LKM 加载失败，请查看日志" ;;
                *) printf '%s' "SUSFS 不可用" ;;
            esac
            ;;
    esac
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
    _v=$(printf '%s' "$_v" | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//')
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
        _v=$(printf '%s' "$_v" | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//')
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

_cf() {
    [ -f "$_CF" ] || return 2
    command -v sha256sum >/dev/null 2>&1 || return 2
    # 同一进程树已完成校验：直接跳过，避免每个启动阶段重复哈希 37MB 的 .ko
    if [ "${SUSFS_CF_OK:-0}" = "1" ]; then return 0; fi
    # 同一 boot 内、清单与发布文件都没变时复用上次结果
    if _cf_cache_ok; then return 0; fi
    # 清单与 meta 交叉校验：只换 .cache.files 不改 .cache.meta 会被发现
    if [ -f "$MODDIR/.cache.meta" ]; then
        _want=$(sed -n 's/^manifest_sha256=//p' "$MODDIR/.cache.meta" 2>/dev/null)
        if [ -n "$_want" ]; then
            _have=$(sha256sum "$_CF" 2>/dev/null | cut -d" " -f1)
            [ "$_want" = "$_have" ] || return 1
        fi
    fi
    _o=$(cd "$MODDIR" 2>/dev/null && sha256sum -c "$_CF" 2>&1) || {
        # toybox 对打不开的文件只打 perror，输出里没有 FAILED 行，改按 OK 行数比对
        _ok_n=$(printf '%s\n' "$_o" | awk '/: OK/{n++} END{print n+0}')
        _all_n=$(grep -c . "$_CF" 2>/dev/null)
        # empty manifest is abnormal: treat as modified (old package without manifest returns 2)
        if [ -z "$_all_n" ] || [ "$_all_n" -eq 0 ] 2>/dev/null; then
            echo "[!] manifest empty"
            return 1
        fi
        if [ "$_ok_n" -lt "$_all_n" ]; then
            echo "[!] $((_all_n - _ok_n)) 个文件与发布包不一致"
            printf '%s\n' "$_o" | grep -v ': OK' | head -3
            return 1
        fi
        return 3
    }
    _cf_cache_write
    return 0
}

# 校验缓存有效性：同一 boot + 清单 mtime 未变 + 清单内文件都比缓存旧
_cf_cache_ok() {
    _cok="$STATE/.cf.ok"
    [ -f "$_cok" ] || return 1
    _cok_bid=$(sed -n 's/^boot_id=//p' "$_cok" 2>/dev/null)
    _cok_mf=$(sed -n 's/^manifest_mtime=//p' "$_cok" 2>/dev/null)
    [ -n "$_cok_bid" ] && [ -n "$_cok_mf" ] || return 1
    [ "$_cok_bid" = "$(cat "${PROC_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}" 2>/dev/null)" ] || return 1
    _cok_now=$(stat -c %Y "$_CF" 2>/dev/null)
    [ -n "$_cok_now" ] && [ "$_cok_mf" = "$_cok_now" ] || return 1
    _cok_mt=$(stat -c %Y "$_cok" 2>/dev/null)
    [ -n "$_cok_mt" ] || return 1
    while IFS= read -r _cok_line || [ -n "$_cok_line" ]; do
        [ -n "$_cok_line" ] || continue
        _cok_p=$(printf '%s' "$_cok_line" | awk '{print $2}')
        [ -n "$_cok_p" ] || return 1
        _cok_fmt=$(stat -c %Y "$MODDIR/$_cok_p" 2>/dev/null)
        _cok_fct=$(stat -c %Z "$MODDIR/$_cok_p" 2>/dev/null)
        [ -n "$_cok_fmt" ] && [ -n "$_cok_fct" ] || return 1
        [ "$_cok_fmt" -lt "$_cok_mt" ] || return 1
        # ctime 不能像 mtime 那样回拨；防「改文件后 touch -t 旧时间」绕过缓存
        [ "$_cok_fct" -lt "$_cok_mt" ] || return 1
    done < "$_CF"
    return 0
}

_cf_cache_write() {
    mkdir -p "$STATE" 2>/dev/null
    _cw_bid=$(cat "${PROC_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}" 2>/dev/null)
    _cw_mf=$(stat -c %Y "$_CF" 2>/dev/null)
    [ -n "$_cw_bid" ] && [ -n "$_cw_mf" ] || return 0
    {
        printf 'boot_id=%s\n' "$_cw_bid"
        printf 'manifest_mtime=%s\n' "$_cw_mf"
    } > "$STATE/.cf.ok.tmp" 2>/dev/null && mv -f "$STATE/.cf.ok.tmp" "$STATE/.cf.ok" 2>/dev/null
    return 0
}

# 启动链路闸门：文件被改就拒绝执行（旧包/工具异常不拦）
_cf_gate() {
    [ "${SUSFS_CF_OK:-0}" = "1" ] && return 0
    _cf 2>/dev/null; _r=$?
    case $_r in
        0|2|3) return 0 ;;
        *)
            echo "[!] 模块文件与发布包不一致，拒绝执行"
            echo "[!] 请从官方仓库重新下载安装"
            return 1
            ;;
    esac
}

_cf_run() {
    mkdir -p "$STATE" 2>/dev/null
    if [ "${SUSFS_CF_OK:-0}" = "1" ]; then printf ok > "$_CFS" 2>/dev/null; return 0; fi
    _cf; _r=$?
    case $_r in
        0) printf ok > "$_CFS" 2>/dev/null; return 0 ;;
        1) printf modified > "$_CFS" 2>/dev/null; return 1 ;;
        *) printf unknown > "$_CFS" 2>/dev/null; return 0 ;;
    esac
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

_cf_state() {
    [ -f "$_CFS" ] || { printf unknown; return 0; }
    _v=$(cat "$_CFS" 2>/dev/null)
    case "$_v" in ok|modified) printf '%s' "$_v" ;; *) printf unknown ;; esac
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
    echo "packaged=$(list_kmis "$MODDIR" | tr '\n' ' ')"
    echo "guessed=$(guess_kmis "$_rel" "$MODDIR" | tr '\n' ' ')"
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

# 只清启动守卫，不动 autoload_paused。用于「没有尝试加载/加载失败」的路径：
# 失败后由 pause_autoload 决定是否暂停，不能在这里把刚写的暂停标记清掉。
clear_boot_guard_keep_pause() {
    rm -f "$(boot_guard_path)" 2>/dev/null
}

clear_boot_guard() {
    clear_boot_guard_keep_pause
    rm -f "$STATE/autoload_paused" 2>/dev/null
}

# 自动加载前的检查：返回 0 表示可以继续，1 表示应暂停自动加载
boot_guard_should_pause() {
    if [ -f "$STATE/autoload_paused" ]; then
        echo "[!] 自动加载处于暂停状态（ctl.sh resume_autoload 恢复）"
        return 1
    fi
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
    pstore_crash_ack 2>/dev/null || true
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
    _hf=$1
    _hb="$_hf.boot"
    _bid=$(cat "${PROC_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}" 2>/dev/null)
    if [ -z "$_bid" ]; then
        # 读不到 boot_id：无法判断是否同一次开机，清空记录保证规则能下发（去重降级）
        : > "$_hf" 2>/dev/null
        return 0
    fi
    [ "$(cat "$_hb" 2>/dev/null)" = "$_bid" ] && return 0
    : > "$_hf" 2>/dev/null
    echo "$_bid" > "$_hb" 2>/dev/null
    return 0
}

# ---- 挂载前缀表（/proc/susfs_hide_mounts）----
# 上游 r18.5+ 把 add_sus_mount / add_try_umount 标为 deprecated，改用它：
#   add <前缀> / del <前缀> / set ... / reset / clear
# 当前 LKM 的容量是 64 个前缀。
HIDE_MOUNTS_NODE=${HIDE_MOUNTS_NODE:-/proc/susfs_hide_mounts}

hide_mounts_supported() {
    [ -e "$HIDE_MOUNTS_NODE" ] || [ -e "/proc/susfs_hide_mounts" ]
}

hide_mounts_write() {
    # $1 = add|del, $2 = 前缀
    _node=$HIDE_MOUNTS_NODE
    [ -e "$_node" ] || _node=/proc/susfs_hide_mounts
    [ -e "$_node" ] || return 1
    printf '%s %s\n' "$1" "$2" > "$_node" 2>/dev/null || return 1
    return 0
}

hide_mounts_add() { hide_mounts_write add "$1"; }

# 回读当前前缀表（节点可读），用于去重
hide_mounts_has() {
    _hmh_node=$HIDE_MOUNTS_NODE
    [ -e "$_hmh_node" ] || _hmh_node=/proc/susfs_hide_mounts
    [ -e "$_hmh_node" ] || return 1
    _hmh_pref=$(sed -n 's/^#[[:space:]]*prefixes:[[:space:]]*//p; s/^prefixes:[[:space:]]*//p' "$_hmh_node" 2>/dev/null)
    [ -n "$_hmh_pref" ] || return 1
    case " $_hmh_pref " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}
hide_mounts_del() { hide_mounts_write del "$1"; }

# 本模块写入的前缀清单，用于 replace_rules=1 时只撤销自己加的部分
own_hide_mounts_file() { printf '%s' "$STATE/hide_mounts_added.txt"; }

# 上游默认前缀：撤销时绝不能删（reset 会回到它们）
HIDE_MOUNTS_DEFAULT_PREFIXES="/data/adb/ /data/local/tmp/"

_hm_norm() {
    case "$1" in
        */) printf '%s' "$1" ;;
        *) printf '%s/' "$1" ;;
    esac
}

record_own_hide_mount() {
    # 默认前缀保护：比较前归一化尾斜杠，/data/adb 与 /data/adb/ 等价
    _hm_n=$(_hm_norm "$1")
    case " $HIDE_MOUNTS_DEFAULT_PREFIXES " in
        *" $_hm_n "*) return 0 ;;
    esac
    grep -Fqx -- "$1" "$(own_hide_mounts_file)" 2>/dev/null && return 0
    mkdir -p "$STATE" 2>/dev/null
    printf '%s\n' "$1" >> "$(own_hide_mounts_file)" 2>/dev/null
}

clear_own_hide_mounts() {
    _hm_f=$(own_hide_mounts_file)
    [ -f "$_hm_f" ] || return 0
    _hm_pend=$STATE/.hm.pend; : > "$_hm_pend" 2>/dev/null
    while IFS= read -r _hm_p || [ -n "$_hm_p" ]; do
        [ -n "$_hm_p" ] || continue
        if hide_mounts_del "$_hm_p" >/dev/null 2>&1; then
            echo "[=] hide_mounts 撤销 $_hm_p"
        else
            printf '%s\n' "$_hm_p" >> "$_hm_pend" 2>/dev/null
        fi
    done < "$_hm_f"
    if [ -s "$_hm_pend" ]; then
        cp -f "$_hm_pend" "$_hm_f" 2>/dev/null
    else
        : > "$_hm_f" 2>/dev/null
    fi
    rm -f "$_hm_pend"
    return 0
}

# ---- mmap 隐藏（/proc/susfs_map，上游 r18.5+ #145）----
# 按 inode 隐藏进程 maps / smaps / map_files / pagemap 里的真实文件路径。
SUS_MAP_NODE=${SUS_MAP_NODE:-/proc/susfs_map}

sus_map_supported() {
    [ -e "$SUS_MAP_NODE" ] || [ -e "/proc/susfs_map" ]
}

sus_map_write() {
    # $1 = add|del|clear, $2 = 路径（clear 时忽略）
    _node=$SUS_MAP_NODE
    [ -e "$_node" ] || _node=/proc/susfs_map
    [ -e "$_node" ] || return 1
    case "$1" in
        clear) printf 'clear\n' > "$_node" 2>/dev/null || return 1 ;;
        *) [ -n "$2" ] || return 1
           printf '%s %s\n' "$1" "$2" > "$_node" 2>/dev/null || return 1 ;;
    esac
    return 0
}

sus_map_add() { sus_map_write add "$1"; }

# 按本次开机去重（内核 /proc/susfs_map 只回显 ino/dev，无法按路径回读）
sus_map_add_once() {
    _smu_hf="$STATE/sus_map_added.txt"
    _mount_dedup_prepare "$_smu_hf"
    grep -Fqx -- "$1" "$_smu_hf" 2>/dev/null && return 2
    sus_map_add "$1" || return 1
    printf '%s\n' "$1" >> "$_smu_hf" 2>/dev/null
    return 0
}
sus_map_del() { sus_map_write del "$1"; }

own_sus_map_file() { printf '%s' "$STATE/sus_map_added.txt"; }

record_own_sus_map() {
    _sm_f=$(own_sus_map_file)
    mkdir -p "$STATE" 2>/dev/null
    grep -Fqx -- "$1" "$_sm_f" 2>/dev/null && return 0
    printf '%s\n' "$1" >> "$_sm_f" 2>/dev/null
}

clear_own_sus_map() {
    _sm_f=$(own_sus_map_file)
    [ -f "$_sm_f" ] || return 0
    _sm_pend=$STATE/.sm.pend; : > "$_sm_pend" 2>/dev/null
    while IFS= read -r _sm_p || [ -n "$_sm_p" ]; do
        [ -n "$_sm_p" ] || continue
        if sus_map_del "$_sm_p" >/dev/null 2>&1; then
            echo "[=] sus_map 撤销 $_sm_p"
        else
            printf '%s\n' "$_sm_p" >> "$_sm_pend" 2>/dev/null
        fi
    done < "$_sm_f"
    if [ -s "$_sm_pend" ]; then
        cp -f "$_sm_pend" "$_sm_f" 2>/dev/null
    else
        : > "$_sm_f" 2>/dev/null
    fi
    rm -f "$_sm_pend"
    return 0
}

# 返回 0=本次已添加，2=之前已添加过（跳过），1=添加失败
sus_mount_add_once() {
    _smo_p=$1
    _smo_hf="$STATE/sus_mount_added.txt"
    _mount_dedup_prepare "$_smo_hf"
    grep -Fqx -- "$_smo_p" "$_smo_hf" 2>/dev/null && return 2
    "$BIN" add_sus_mount "$_smo_p" >/dev/null 2>&1 || return 1
    printf '%s\n' "$_smo_p" >> "$_smo_hf" 2>/dev/null
    return 0
}

try_umount_add_once() {
    _tu_p=$1
    _tu_hf="$STATE/try_umount_added.txt"
    _mount_dedup_prepare "$_tu_hf"
    grep -Fqx -- "$_tu_p" "$_tu_hf" 2>/dev/null && return 2
    "$BIN" add_try_umount "$_tu_p" 1 >/dev/null 2>&1 || return 1
    printf '%s\n' "$_tu_p" >> "$_tu_hf" 2>/dev/null
    return 0
}

# ---- 运行时锁与耗时判断 ----
# mkdir 是原子的：用它做简单互斥，避免开机 apply 与 WebUI apply 同时写规则
lock_acquire() {
    _lk=$1; _ttl=${2:-900}
    mkdir -p "$STATE" 2>/dev/null
    _bid=$(cat "${PROC_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}" 2>/dev/null)
    # 锁目录里记录持有者 PID：过期被接管后，旧持有者退出时不能删掉新锁
    mkdir "$_lk" 2>/dev/null && { echo "$$ $_bid" > "$_lk/pid" 2>/dev/null; return 0; }
    # 上一次开机留下的锁：boot_id 不同，直接接管（不再等 TTL）
    _lk_bid=$(cut -d" " -f2 "$_lk/pid" 2>/dev/null)
    if [ -n "$_lk_bid" ] && [ -n "$_bid" ] && [ "$_lk_bid" != "$_bid" ]; then
        rm -rf "$_lk" 2>/dev/null
        mkdir "$_lk" 2>/dev/null && { echo "$$ $_bid" > "$_lk/pid" 2>/dev/null; return 0; }
    fi
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
            mkdir "$_lk" 2>/dev/null && { echo "$$ $_bid" > "$_lk/pid" 2>/dev/null; return 0; }
        fi
    fi
    return 1
}

lock_release() {
    # 只释放自己持有的锁
    if [ -f "$1/pid" ] && [ "$(cut -d" " -f1 "$1/pid" 2>/dev/null)" != "$$" ]; then
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
    _sp_p=$1
    [ -n "$_sp_p" ] || return 1
    [ -e "$SUSFS_PATH_NODE" ] || return 1
    echo "del $_sp_p" >> "$SUSFS_PATH_NODE" 2>/dev/null
    # 内核可能对不存在的规则静默成功：回读确认这一行确实消失
    ! grep -F -q "path=$_sp_p " "$SUSFS_PATH_NODE" 2>/dev/null
}

# 记录本模块成功写入的路径（去重）
record_our_path() {
    _rp_p=$1
    [ -n "$_rp_p" ] || return 0
    _rp_f=$(our_paths_file)
    mkdir -p "$STATE" 2>/dev/null
    grep -Fqx -- "$_rp_p" "$_rp_f" 2>/dev/null || printf '%s\n' "$_rp_p" >> "$_rp_f"
}

# replace_rules=1：只移除上一次记录的路径
clear_own_paths() {
    _op_f=$(our_paths_file)
    if [ ! -s "$_op_f" ]; then
        echo "[i] 无历史规则清单，跳过清理（不触碰其他模块的规则）"
        return 0
    fi
    _op_n=0; _op_fail=0
    _op_pending="$STATE/our_paths.pending.txt"
    : > "$_op_pending" 2>/dev/null
    while IFS= read -r _op_p || [ -n "$_op_p" ]; do
        [ -n "$_op_p" ] || continue
        if susfs_path_del "$_op_p"; then
            _op_n=$((_op_n + 1))
        else
            _op_fail=$((_op_fail + 1))
            printf '%s\n' "$_op_p" >> "$_op_pending" 2>/dev/null
        fi
    done < "$_op_f"
    # 删除失败的条目留在清单里，下次继续尝试，避免变成无法清理的孤儿规则
    if [ -s "$_op_pending" ]; then
        mv -f "$_op_pending" "$_op_f" 2>/dev/null
    else
        : > "$_op_f"
        rm -f "$_op_pending" 2>/dev/null
    fi
    echo "[i] 已移除本模块上次写入的规则: 成功 $_op_n 条，失败 $_op_fail 条"
    if [ "$_op_n" = "0" ] && [ "$_op_fail" -gt 0 ]; then
        echo "[!] 当前内核不支持 del，旧规则无法逐条移除；如需整表清空请显式设置 replace_rules=2"
    fi
}

# 去掉注释：只认行首或空白后的 #，路径里的 # 原样保留
strip_comment() {
    _sk_v=$(printf '%s' "$1" | tr -d '\r')
    _sk_v=$(printf '%s' "$_sk_v" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$_sk_v" in
        '#'*) _sk_v="" ;;
        *) _sk_v=$(printf '%s' "$_sk_v" | sed 's/[[:space:]]#.*$//'); _sk_v=$(printf '%s' "$_sk_v" | sed 's/[[:space:]]*$//') ;;
    esac
    printf '%s' "$_sk_v"
}

# 首次迁移：旧版本用整表 clear 写入规则，没有留下清单。
# 以当前配置里声明的路径为候选逐条删除，只动配置内的路径。
clear_migrated_paths() {
    _cmp_cfg=$1
    [ -f "$_cmp_cfg" ] || return 0
    _cmp_n=0; _cmp_fail=0
    while IFS= read -r _cmp_line || [ -n "$_cmp_line" ]; do
        _cmp_p=$(strip_comment "$_cmp_line")
        [ -n "$_cmp_p" ] || continue
        case "$_cmp_p" in /*) ;; *) continue ;; esac
        if susfs_path_del "$_cmp_p"; then _cmp_n=$((_cmp_n + 1)); else _cmp_fail=$((_cmp_fail + 1)); fi
    done < "$_cmp_cfg"
    echo "[i] 首次迁移：按配置清理旧规则 成功 $_cmp_n 条，失败 $_cmp_fail 条"
    [ "$_cmp_n" = "0" ] && [ "$_cmp_fail" -gt 0 ] && echo "[!] 内核不支持 del，旧规则无法逐条移除"
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
    for _f in config.ini sus_path.txt sus_mount.txt try_umount.txt hide_modules.txt skip_hide.txt sus_map.txt; do
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
    for _f in config.ini config.ini.default sus_path.txt sus_mount.txt try_umount.txt hide_modules.txt skip_hide.txt sus_map.txt; do
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
    _sfe_feat=$1
    [ -n "$_sfe_feat" ] || return 1
    _sfe_b=$(select_susfs_bin 2>/dev/null) || return 1
    "$_sfe_b" show enabled_features 2>/dev/null | grep -qx "$_sfe_feat"
}

# 记录一次实测失败：把该能力标记为不可用，避免重复尝试
caps_downgrade() {
    _cd_name=$1
    _cd_f="$STATE/$CAPS_FILE_NAME"
    [ -f "$_cd_f" ] || caps_refresh
    [ -f "$_cd_f" ] || return 0
    # 用 awk 重写，避免依赖 sed -i（部分机型/toybox 行为不一致）
    awk -v n="$_cd_name" '
        BEGIN { done = 0; src = 0 }
        $0 ~ "^" n "=" { print n "=0"; done = 1; next }
        $0 ~ "^" n "_src=" { print n "_src=probe"; src = 1; next }
        { print }
        END { if (!done) print n "=0"; if (!src) print n "_src=probe" }
    ' "$_cd_f" > "$_cd_f.tmp" 2>/dev/null && mv -f "$_cd_f.tmp" "$_cd_f" 2>/dev/null
}

caps_refresh() {
    mkdir -p "$STATE" 2>/dev/null
    _cr_f="$STATE/$CAPS_FILE_NAME"
    # 只读判定：特性位可能谎报（上游 #122），实测失败时由 caps_downgrade 降级为 0
    {
        if susfs_feature_enabled CONFIG_KSU_SUSFS_SUS_MOUNT; then echo "sus_mount=1"; else echo "sus_mount=0"; fi
        echo "sus_mount_src=feature"
        if susfs_feature_enabled CONFIG_KSU_SUSFS_TRY_UMOUNT; then echo "try_umount=1"; else echo "try_umount=0"; fi
        echo "try_umount_src=feature"
        echo "lkm=$([ -d /sys/module/susfs_guard_lkm ] && echo 1 || echo 0)"
        echo "boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
        echo "checked_at=$(date '+%F %T' 2>/dev/null)"
    } > "$_cr_f" 2>/dev/null
}

cap_ok() {
    _cap_f="$STATE/$CAPS_FILE_NAME"
    _cap_bid=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
    _cap_cached=$(grep '^boot_id=' "$_cap_f" 2>/dev/null | tail -1 | cut -d= -f2-)
    # LKM 装载状态也要参与判定：未加载时判定出的 0 不能留到加载之后
    _cap_lk=$([ -d /sys/module/susfs_guard_lkm ] && echo 1 || echo 0)
    _cap_cached_lk=$(grep '^lkm=' "$_cap_f" 2>/dev/null | tail -1 | cut -d= -f2-)
    if [ ! -f "$_cap_f" ] || { [ -n "$_cap_bid" ] && [ "$_cap_bid" != "$_cap_cached" ]; } || [ "$_cap_lk" != "$_cap_cached_lk" ]; then
        caps_refresh
    fi
    [ "$(grep "^$1=" "$_cap_f" 2>/dev/null | tail -1 | cut -d= -f2)" = "1" ]
}
# ---- 诊断：ksu_susfs 通信失败排查 ----
# 输出两个二进制对同一内核的响应，便于判断是二进制 ABI 不匹配还是 LKM 问题。
diag_tooling() {
    echo "osrelease=$(cat /proc/sys/kernel/osrelease 2>/dev/null)"
    . "$MODDIR/kmi.sh" 2>/dev/null
    echo "kmi=$(select_kmi "$(cat /proc/sys/kernel/osrelease 2>/dev/null)" "$MODDIR" 2>/dev/null)"
    echo "susfs_kernel=$(susfs_kernel_kind)"
    if lkm_present; then echo "lkm_marker=1"; else echo "lkm_marker=0"; fi
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
    _elf_f=$1
    [ -f "$_elf_f" ] || { echo "missing"; return 0; }
    _elf_magic=$(od -An -tx1 -N4 "$_elf_f" 2>/dev/null | tr -d " \n")
    [ "$_elf_magic" = "7f454c46" ] || { echo "not-elf"; return 0; }
    _elf_lo=$(od -An -tu1 -j18 -N1 "$_elf_f" 2>/dev/null | tr -d " ")
    _elf_hi=$(od -An -tu1 -j19 -N1 "$_elf_f" 2>/dev/null | tr -d " ")
    _elf_m=$(( ${_elf_hi:-0} * 256 + ${_elf_lo:-0} ))
    case "$_elf_m" in
        183) echo "aarch64" ;;
        62)  echo "x86_64" ;;
        40)  echo "arm" ;;
        3)   echo "x86" ;;
        *)   echo "machine=$_elf_m" ;;
    esac
}
# 判断是否为「检测类应用自身的数据目录」：隐藏它们会让检测工具行为异常，
# 反而更容易被判为异常环境，因此默认跳过。
# 若 skip_hide.txt 缺失（例如升级时配置目录被跳过），按默认列表生成一份
ensure_skip_hide_file() {
    _esh_f="$CONFIG/skip_hide.txt"
    [ -f "$_esh_f" ] && return 0
    mkdir -p "$CONFIG" 2>/dev/null
    {
        echo "# 不隐藏的包名/路径片段，每行一个（子串匹配，支持 # 注释）"
        echo "# 隐藏检测类应用自己的数据目录会让它判定异常，需要时把包名加到这里"
        echo "duckdetector"
        echo "appvisibility"
        echo "nativecheck"
    } > "$_esh_f" 2>/dev/null && echo "[i] 已生成默认 config/skip_hide.txt"
}

# 需要跳过隐藏的包名从 config/skip_hide.txt 读取（每行一个子串，支持 # 注释）
is_detection_app_path() {
    _dia_p=$1
    [ -n "$_dia_p" ] || return 1
    _dia_f="$CONFIG/skip_hide.txt"
    [ -f "$_dia_f" ] || return 1
    while IFS= read -r _dia_pat || [ -n "$_dia_pat" ]; do
        _dia_pat=$(strip_comment "$_dia_pat")
        [ -n "$_dia_pat" ] || continue
        case "$_dia_p" in *"$_dia_pat"*) return 0 ;; esac
    done < "$_dia_f"
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