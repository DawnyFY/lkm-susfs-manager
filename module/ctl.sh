#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# WebUI 后端：只接受白名单命令，所有操作以 root 身份执行。
# 模块路径必须固定：不允许调用方用环境变量把配置写到模块目录以外
MODDIR=/data/adb/modules/susfs_allinone
CONFIG=$MODDIR/config
STATE=$MODDIR/state
. "$MODDIR/common.sh"

get_prop() {
    grep "^$1=" "$MODDIR/module.prop" 2>/dev/null | cut -d= -f2-
}

valid_b64() {
    case "$1" in
        *[!A-Za-z0-9+/=]*) return 1 ;;
        *) return 0 ;;
    esac
}

# Probe PID Guard 的状态字段：status 与 pid_guard_bundle 共用，避免两处逻辑漂移
pg_status_fields() {
    # 全部用内建读取：原来这里是 3 次 grep|cut（配置）+ 2 次 grep -qw（/proc）
    # + 1 次 grep|cut（状态文件），共 7 个进程，是 status 里除探测之外最大的一块。
    _PG_EN=0
    _PG_UIDS=""
    _PG_COMMS=""
    if [ -f "$CONFIG/pid_guard.conf" ]; then
        while IFS='=' read -r _k _v; do
            case "$_k" in
                enabled) _PG_EN=$_v ;;
                target_uids) _PG_UIDS=$_v ;;
                target_comms) _PG_COMMS=$_v ;;
            esac
        done < "$CONFIG/pid_guard.conf"
    fi
    case "$_PG_EN" in 0|1) ;; *) _PG_EN=0 ;; esac
    _PG_LOADED=0
    [ -d /sys/module/generic_pid_guard ] && _PG_LOADED=1
    _PG_VISIBLE=0
    if [ -r /proc/modules ]; then
        while read -r _m _rest; do
            [ "$_m" = "generic_pid_guard" ] && { _PG_VISIBLE=1; break; }
        done < /proc/modules
    fi
    _PG_HIDDEN=0
    # 只有真的加载了才算「已隐藏」：卸载后残留的名字不该让页面显示已隐藏
    if [ "$_PG_LOADED" = "1" ]; then
        hide_list_has generic_pid_guard && _PG_HIDDEN=1
    fi
    _PG_RES=""
    if [ -f "$STATE/pid_guard.status" ]; then
        while IFS='=' read -r _k _v; do
            [ "$_k" = "result" ] && _PG_RES=$_v
        done < "$STATE/pid_guard.status"
    fi
    printf 'pid_guard_enabled=%s\n' "$_PG_EN"
    printf 'pid_guard_loaded=%s\n' "$_PG_LOADED"
    printf 'pid_guard_visible=%s\n' "$_PG_VISIBLE"
    printf 'pid_guard_hidden=%s\n' "$_PG_HIDDEN"
    printf 'pid_guard_result=%s\n' "${_PG_RES:-unknown}"
    printf 'pid_guard_uids=%s\n' "$_PG_UIDS"
    printf 'pid_guard_comms=%s\n' "$_PG_COMMS"
}

# status 的探测缓存：同一 boot 内只算一次。
# 这些探测每项要起一个进程（ksu_susfs / getprop / 内核日志 / config.gz），
# status 每次刷新都重算的话，光是进程创建就 1.5s。
# ksu_susfs 的版本指纹按 size+mtime 参与，换二进制自动失效。
_st_probe_signature() {
    _sig_bid=""
    read -r _sig_bid < /proc/sys/kernel/random/boot_id 2>/dev/null
    _sig_bin=""
    _sig_bin_path=$(select_susfs_bin_fast 2>/dev/null)
    if [ -n "$_sig_bin_path" ] && [ -x "$_sig_bin_path" ]; then
        _sig_bin=$(stat -c '%s-%Y' "$_sig_bin_path" 2>/dev/null)
    fi
    # LKM 是否已装载必须参与签名：先看状态、后加载 LKM 的用户，
    # 若沿用旧签名会一直拿到 ksu_bin=incompatible（audit M1b）
    _sig_lkm=0
    [ -d /sys/module/susfs_guard_lkm ] && _sig_lkm=1
    printf '%s|%s|%s' "$_sig_bid" "$_sig_bin" "$_sig_lkm"
}

_st_probe_refresh() {
    _BIN=$(select_susfs_bin_fast 2>/dev/null)
    _VARIANT=""
    _VERSION=""
    _BIN_OK=0
    if [ -n "$_BIN" ] && [ -x "$_BIN" ]; then
        # version 与 variant 各要几百毫秒（每次起一个进程读内核侧信息），并行跑
        _tmpv="$STATE/.binver.$$"
        _tmpa="$STATE/.binvar.$$"
        mkdir -p "$STATE" 2>/dev/null
        "$_BIN" show version >"$_tmpv" 2>/dev/null &
        _pidv=$!
        _pida=""
        if [ -d /sys/module/susfs_guard_lkm ]; then
            "$_BIN" show variant >"$_tmpa" 2>/dev/null &
            _pida=$!
        fi
        wait "$_pidv" 2>/dev/null && _BIN_OK=1
        [ -n "$_pida" ] && wait "$_pida" 2>/dev/null
        [ -s "$_tmpv" ] && read -r _VERSION < "$_tmpv" 2>/dev/null
        [ -s "$_tmpa" ] && read -r _VARIANT < "$_tmpa" 2>/dev/null
        rm -f "$_tmpv" "$_tmpa" 2>/dev/null
    fi
    if kernelpatch_present; then _KP=1; else _KP=0; fi
    _IID=$(install_id 2>/dev/null)
    _SE=$(getenforce 2>/dev/null)
    _RM=$(ksu_branch 2>/dev/null)
    _BL=$(bootloader_state 2>/dev/null)
    _KPS=$(kernelpatch_kernel_state 2>/dev/null)
    _KPV=$(kernelpatch_kernel_version 2>/dev/null)
    _CKSU=$(kernel_config_get CONFIG_KSU 2>/dev/null)
    _CKSUSFS=$(kernel_config_get CONFIG_KSU_SUSFS 2>/dev/null)
    _pc_tmp="$STATE/.probe_cache.$$"
    {
        printf 'sig=%s' "$(_st_probe_signature)"
        printf '%s' "
bin=$_BIN
bin_ok=$_BIN_OK
variant=$_VARIANT
version=$_VERSION
kp=$_KP
iid=$_IID
se=$_SE
rm=$_RM
bl=$_BL
kps=$_KPS
kpv=$_KPV
cksu=$_CKSU
cksusfs=$_CKSUSFS
"
        printf 'ok=1\n'
    } > "$_pc_tmp" 2>/dev/null && mv -f "$_pc_tmp" "$STATE/.probe_cache" 2>/dev/null || rm -f "$_pc_tmp" 2>/dev/null
}

# 读缓存到 _P_*；返回值 0 表示命中
_st_probe_load() {
    _pc="$STATE/.probe_cache"
    [ -f "$_pc" ] || return 1
    _want=$(_st_probe_signature)
    _have=""
    read -r _first < "$_pc" 2>/dev/null
    case "$_first" in sig=*) _have=${_first#sig=} ;; esac
    [ "$_have" = "$_want" ] || return 1
    _P_BIN=""; _P_BIN_OK=0; _P_VARIANT=""; _P_VERSION=""
    _P_KP=0; _P_IID=""; _P_SE=""; _P_RM=""; _P_BL=""; _P_KPS=""; _P_KPV=""
    _P_CKSU=""; _P_CKSUSFS=""
    _P_OK=0
    while IFS='=' read -r _k _v; do
        case "$_k" in
            bin) _P_BIN=$_v ;;
            bin_ok) _P_BIN_OK=$_v ;;
            variant) _P_VARIANT=$_v ;;
            version) _P_VERSION=$_v ;;
            kp) _P_KP=$_v ;;
            iid) _P_IID=$_v ;;
            se) _P_SE=$_v ;;
            rm) _P_RM=$_v ;;
            bl) _P_BL=$_v ;;
            kps) _P_KPS=$_v ;;
            kpv) _P_KPV=$_v ;;
            cksu) _P_CKSU=$_v ;;
            cksusfs) _P_CKSUSFS=$_v ;;
            ok) _P_OK=$_v ;;
        esac
    done < "$_pc"
    # 半写/被截断的缓存不能当命中：否则整个 boot 都会用空值（audit M3）
    [ "$_P_OK" = "1" ] || return 1
    return 0
}

status() {
    REL=$(real_kernel_release 2>/dev/null)
    [ -n "$REL" ] || REL=$(cat /proc/sys/kernel/osrelease 2>/dev/null)
    KMI=unknown
    if [ -f "$MODDIR/kmi.sh" ] && [ -n "$REL" ]; then
        . "$MODDIR/kmi.sh"
        KMI=$(select_kmi "$REL" "$MODDIR" 2>/dev/null) || KMI=unknown
    fi

    _susfs_detect
    SUSFS_KIND=$_SUSFS_KIND
    PRESENT=0
    [ "$SUSFS_KIND" != "none" ] && PRESENT=1
    LKM_PRESENT=0
    [ "$SUSFS_KIND" = "lkm" ] && LKM_PRESENT=1

    # 一键探测：命中缓存就不起任何进程；未命中才重算一次（每 boot 一次）
    if ! _st_probe_load; then
        _st_probe_refresh
        _st_probe_load || true
    fi
    BIN=$_P_BIN

    VARIANT=$_P_VARIANT
    VERSION=$_P_VERSION
    _BIN_OK=$_P_BIN_OK

    # 活动二进制存在但跑不起来时，回退到模块自带备份：
    # 1.2.7 的 select_susfs_bin 就是这么做的（bin/ksu_susfs_good 存在的意义），
    # 只用 fast 选择器会停在坏的那支，导致 ksu_bin=incompatible、版本号为空。
    if [ "$_BIN_OK" = "0" ] && [ "$LKM_PRESENT" = "1" ]; then
        _bk=$(find_susfs_backup 2>/dev/null)
        if [ -n "$_bk" ] && [ "$_bk" != "$BIN" ] && [ -x "$_bk" ]; then
            if _vb=$("$_bk" show version 2>/dev/null); then
                BIN=$_bk
                VERSION=$_vb
                _BIN_OK=1
                VARIANT=$("$_bk" show variant 2>/dev/null)
            fi
        fi
    fi

    # 规则数：原先 grep|grep|sed|awk|sort|wc 六段管线要起 6 个进程，改成一次读 + 内建判重
    RULES=0
    if [ -r /proc/susfs_path ]; then
        _seen_rules=" "
        while read -r _line; do
            case "$_line" in path=*) ;; *) continue ;; esac
            case "$_line" in *"[ours:"*) continue ;; esac
            _p=${_line#path=}
            _p=${_p%% *}
            case "$_seen_rules" in *" $_p "*) continue ;; esac
            _seen_rules="$_seen_rules$_p "
            RULES=$((RULES + 1))
        done < /proc/susfs_path
    fi
    HIDE=0
    hide_list_has kernelsu && HIDE=1
    MARKER=0
    marker_exists && MARKER=1

    auto_load=1
    cfg_ensure 2>/dev/null
    cfg_load 2>/dev/null
    AUTOLOAD=${auto_load:-1}
    [ -f "$MODDIR/disable_autoload" ] && AUTOLOAD=0

    KSSTAT=missing
    if [ -n "$BIN" ] && [ -x "$BIN" ]; then
        if [ "$PRESENT" = "1" ]; then
            [ "$_BIN_OK" = "1" ] && KSSTAT=ok || KSSTAT=incompatible
        else
            KSSTAT=ok
        fi
    fi
    FAILS=""
    read -r FAILS < "$MODDIR/state/fail_count" 2>/dev/null
    FAILS=${FAILS:-0}
    LSIZE=$(stat -c %s "$MODDIR/lib/susfs_guard_lkm-$KMI.ko" 2>/dev/null)
    LSIZE=${LSIZE:-0}

    _prop_version=""
    _prop_desc=""
    if [ -r "$MODDIR/module.prop" ]; then
        while IFS='=' read -r _pk _pv; do
            case "$_pk" in
                version) _prop_version=$_pv ;;
                description) _prop_desc=$_pv ;;
            esac
        done < "$MODDIR/module.prop"
    fi
    printf 'module_version=%s\n' "$_prop_version"
    printf 'install_id=%s\n' "$_P_IID"
    printf 'description=%s\n' "$_prop_desc"
    printf 'kernel=%s\n' "$REL"
    printf 'kmi=%s\n' "$KMI"
    printf 'lkm_present=%s\n' "$LKM_PRESENT"
    printf 'susfs_kernel=%s\n' "$SUSFS_KIND"
    printf 'lkm_variant=%s\n' "$VARIANT"
    printf 'lkm_version=%s\n' "$VERSION"
    printf 'rules=%s\n' "$RULES"
    printf 'hide_kernelsu=%s\n' "$HIDE"
    printf 'marker=%s\n' "$MARKER"
    printf 'auto_load=%s\n' "$AUTOLOAD"
    printf 'root_manager=%s\n' "$_P_RM"
    printf 'ksu_bin=%s\n' "$KSSTAT"
    printf 'ksu_bin_path=%s\n' "$BIN"
    printf 'selinux=%s\n' "$_P_SE"
    printf 'fail_count=%s\n' "$FAILS"
    _AF=""
    read -r _AF < "$STATE/apply_fails" 2>/dev/null
    _AF=${_AF:-0}
    case "$_AF" in ''|*[!0-9]*) _AF=0 ;; esac
    printf 'apply_fails=%s\n' "$_AF"

    pg_status_fields
    _KP=$_P_KP
    printf 'kernelpatch=%s\n' "$_KP"
    printf 'apatch_userland=%s\n' "$_KP"
    printf 'kernelpatch_kernel=%s\n' "$_P_KPS"
    printf 'kernelpatch_version=%s\n' "$_P_KPV"
    printf 'coexist_mode=%s\n' "$([ "$_KP" = "1" ] && echo apatch || echo none)"
    printf 'allow_lkm=%s\n' "$([ -f "$CONFIG/allow_lkm_on_kernelpatch" ] && echo 1 || echo 0)"
    printf 'config_ksu=%s\n' "$_P_CKSU"
    printf 'config_ksu_susfs=%s\n' "$_P_CKSUSFS"
    _AR=""
    read -r _AR < "$STATE/apply_result" 2>/dev/null
    # 本次开机没 apply 过就别报上次的结果（audit M4）：apply_result_boot 记的是产生它的 boot_id
    _ARB=""
    read -r _ARB < "$STATE/apply_result_boot" 2>/dev/null
    _CURBID=""
    read -r _CURBID < /proc/sys/kernel/random/boot_id 2>/dev/null
    if [ -n "$_AR" ] && [ -n "$_ARB" ] && [ -n "$_CURBID" ] && [ "$_ARB" != "$_CURBID" ]; then
        printf 'apply_result=stale:%s\n' "$_AR"
    else
        printf 'apply_result=%s\n' "${_AR:-not_tested}"
    fi
    if [ -f "$STATE/boot_stage_completed" ]; then
        _bst=""
        read -r _bst < "$STATE/boot_stage_completed" 2>/dev/null
        printf 'boot_stage_completed=%s\n' "$_bst"
    else
        printf 'boot_stage_completed=no\n'
    fi
    printf 'backend_kind=%s\n' "$SUSFS_KIND"
    if [ "$SUSFS_KIND" = "builtin" ]; then printf 'backend_interface_detected=1\n'; else printf 'backend_interface_detected=0\n'; fi
    printf 'abi_match=unknown\n'
    printf 'effect_verified=not_tested\n'
    case "$KSSTAT" in
        ok) printf 'tool_query=ok\n' ;;
        incompatible) printf 'tool_query=incompatible\n' ;;
        *) printf 'tool_query=missing\n' ;;
    esac
    if pstore_crash_suspect; then
        printf 'crash_evidence=observed\n'
    elif _cr_fc=$(pstore_crash_foreign) && [ -n "$_cr_fc" ]; then
        printf 'crash_evidence=foreign:%s\n' "$_cr_fc"
    elif pstore_crash_unknown; then
        printf 'crash_evidence=unknown\n'
    elif [ -d /sys/fs/pstore ]; then
        printf 'crash_evidence=not_observed\n'
    else
        printf 'crash_evidence=unavailable\n'
    fi
    printf 'lkm_size=%s\n' "$LSIZE"
    if autoload_paused; then printf 'autoload=paused\n'; else printf 'autoload=ok\n'; fi
    if cap_ok sus_mount; then printf 'sus_mount=ok\n'; else printf 'sus_mount=unsupported\n'; fi
    if cap_ok try_umount; then printf 'try_umount=ok\n'; else printf 'try_umount=unsupported\n'; fi
    printf 'bootloader=%s\n' "$_P_BL"
    printf 'force_bl_unlocked=%s\n' "$(cfg_force_bl)"
    # 校验结果超过 60 秒视为陈旧，重算一次（只写本地状态文件）
    _age=999
    if [ -f "$STATE/.cache.idx" ]; then
        _now=$(date +%s 2>/dev/null); _mt=$(stat -c %Y "$STATE/.cache.idx" 2>/dev/null)
        case "$_now$_mt" in *[!0-9]*) _age=999 ;; *) [ -n "$_now" ] && [ -n "$_mt" ] && _age=$((_now - _mt)) ;; esac
    fi
    [ "$_age" -gt 60 ] && _cf_run >/dev/null 2>&1 || true
    printf 'integrity=%s\n' "$(_cf_state)"
    # WebUI 的隐私开关读这个字段（此前 49 个字段里没有它 → 界面永远显示"开"）
    printf 'anonymous_stats=%s\n' "$(cfg_get anonymous_stats 1)"
}

# 校验 config 文件：只允许注释、空行与 KEY=VALUE；值必须是紧凑 token。
# 成功返回 0；失败把原因打到 stdout 并返回 1。
validate_config_file() {
    _vf=$1
    _bad=""
    _ln=0
    _seen=""
    while IFS= read -r _line || [ -n "$_line" ]; do
        _ln=$((_ln + 1))
        case "$_line" in
            ""|"#"*) continue ;;
        esac
        case "$_line" in
            [A-Za-z_]*=*) ;;
            *) _bad="line $_ln: not KEY=VALUE"; break ;;
        esac
        _key=${_line%%=*}
        _val=${_line#*=}
        # 拒绝重复键：cfg_get 取最后一个、WebUI 也取最后一个，但重复键本身就是配置错误
        case " $_seen " in
            *" $_key "*) _bad="line $_ln: duplicate key $_key"; break ;;
        esac
        _seen="$_seen $_key"
        case "$_key" in
            *[!A-Za-z0-9_]*) _bad="line $_ln: bad key"; break ;;
        esac
        case "$_key" in
            PATH|LD_PRELOAD|LD_LIBRARY_PATH|IFS|ENV|BASH_ENV|PS4|SHELLOPTS|BASHOPTS|CDPATH|GLOBIGNORE|MODDIR|MODPATH|CONFIG|STATE|LOG|BIN|SUSFS_BIN|REL|KMI|FORCE_KMI|force_bl_unlocked)
                _bad="line $_ln: reserved key $_key"; break ;;
        esac
        case "$_key" in
            # cmdline 值天然含空格；只放行空白与普通字符，元字符仍然拒绝
            fake_cmdline_value)
                # 允许空白；引号/反斜杠仍然拒绝（之前空白分支把检查跳过了）
                case "$_val" in
                    *\"*|*'"'*|*\\*) _bad="line $_ln: quote or backslash in value"; break ;;
                esac
                ;;
            *)
                case "$_val" in
                    *[[:space:]]*) _bad="line $_ln: whitespace in value"; break ;;
                    *\"*|*'"'*|*\\*) _bad="line $_ln: quote or backslash in value"; break ;;
                esac
                ;;
        esac
        case "$_val" in
            *[\`\$\;\&\|\<\>\(\)\#\{\}\!\?\~\*]*|*\[*|*\]*)
                _bad="line $_ln: shell metacharacter in value"; break ;;
        esac
    done < "$_vf"
    if [ -n "$_bad" ]; then
        echo "$_bad"
        return 1
    fi
    sh -n "$_vf" 2>/dev/null || { echo "shell syntax error"; return 1; }
    return 0
}

case "$1" in
    status)
        status
        ;;
    install_id)
        install_id
        ;;
    report_install)
        report_install
        ;;
    kmiinfo)
        kmiinfo
        echo "--- real ---"
        if [ -f "$STATE/real_uname.txt" ]; then
            grep -E "^(release|version|saved_at)=" "$STATE/real_uname.txt"
        else
            echo "real_uname=未记录"
        fi
        echo "--- install ---"
        if [ -f "$MODDIR/install_kmi.txt" ]; then
            grep -vE "^(#|$)" "$MODDIR/install_kmi.txt"
        else
            echo "install_record=无（安装时已自动匹配）"
        fi
        ;;
    restore_uname)
        restore_real_uname
        ;;
    resume_autoload)
        resume_autoload
        ;;
    compat)
        compat_check
        exit 0
        ;;
    diag)
        diag_tooling
        exit 0
        ;;
    caps)
        caps_refresh
        cat "$STATE/$CAPS_FILE_NAME" 2>/dev/null
        exit 0
        ;;
    rescan_scene)
        _cf_gate || { echo "文件与发布包不一致，拒绝执行"; exit 1; }
        # 立即重扫 /dev 下的 Scene 痕迹目录（名字随机，按内容特征识别）
        BIN=$(select_susfs_bin 2>/dev/null) || { echo "no ksu_susfs"; exit 1; }
        _rs_n=0
        for _rs_f in /dev/*/scene_mode_category; do
            [ -e "$_rs_f" ] || continue
            _rs_d=${_rs_f%/scene_mode_category}
            if "$BIN" add_sus_path "$_rs_d" >/dev/null 2>&1; then
                record_our_path "$_rs_d"
                echo "hidden $_rs_d"
                _rs_n=$((_rs_n + 1))
            else
                echo "exists $_rs_d"
            fi
            "$BIN" add_sus_path "$_rs_f" >/dev/null 2>&1 && record_our_path "$_rs_f"
        done
        if [ "$_rs_n" = "0" ]; then
            echo "none"
        fi
        exit 0
        ;;
    preset_paths)
        # 输出候选隐藏路径：path<TAB>是否存在<TAB>是否已在 sus_path 里
        # 前端只展示「存在」的项，已加入的置灰
        _cur="$CONFIG/sus_path.txt"
        _rules=" "
        if [ -f "$_cur" ]; then
            while IFS= read -r _rl; do
                case "$_rl" in ''|'#'*) continue ;; esac
                _rules="$_rules$_rl "
            done < "$_cur"
        fi
        for _p in /data/adb/ksu /data/adb/ap /data/adb/magisk /data/adb/modules \
                  /data/adb/ksu/bin /data/adb/ap/bin \
                  /data/adb/ksu/susfs4ksu /data/adb/ap/susfs4ksu /data/adb/susfs4ksu \
                  /data/adb/ksu/modules /data/adb/ap/modules \
                  /data/adb/post-fs-data.d /data/adb/service.d \
                  /data/swap_config.conf \
                  /data/local/stryker /data/local/tmp/luckys \
                  /data/local/tmp/HyperCeiler /data/local/tmp/simpleHook \
                  /data/local/tmp/resetprop \
                  /data/adb/mount_mask /data/adb/mount_mark \
                  /data/local/tmp/mount_mask /data/local/tmp/mount_mark \
                  /data/local/tmp/brevent \
                  /data/local/tmp/AppRetention /data/local/AppRetention; do
            _ex=0
            if [ -e "$_p" ]; then _ex=1; fi
            _in=0
            case "$_rules" in *" $_p "*) _in=1 ;; esac
            printf '%s\t%s\t%s\n' "$_p" "$_ex" "$_in"
        done
        # Scene 痕迹目录名随机，不放进预设（用「隐藏 Scene 痕迹」开关 + 重扫处理）
        ;;
    detect_self)
        # 自检：应用层扫描器（Duck Detector 之类）能看到的、可能归到本模块的痕迹。
        # 用来对账「报告里哪条是本模块的、哪条是 root 管理器/ROM 的」。
        echo "# 本模块暴露面自检 $(now_stamp)"
        printf 'module_version=%s\n' "$(cfg_get_prop version 2>/dev/null || sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null)"
        if [ -f "$MODDIR/kmi.sh" ]; then
            . "$MODDIR/kmi.sh"
            printf 'kmi=%s\n' "$(select_kmi "$(real_kernel_release 2>/dev/null)" "$MODDIR" 2>/dev/null)"
        else
            printf 'kmi=\n'
        fi
        # /proc/modules：hide_modules 生效时本模块与 kernelsu 都不该出现
        if grep -q "susfs_guard_lkm" /proc/modules 2>/dev/null; then
            printf 'proc_modules_susfs=visible\n'
        else
            printf 'proc_modules_susfs=hidden\n'
        fi
        if grep -qi "kernelsu\|kernelsu_next\|ksu" /proc/modules 2>/dev/null; then
            printf 'proc_modules_ksu=visible\n'
        else
            printf 'proc_modules_ksu=hidden\n'
        fi
        # kallsyms：只给计数，符号名无法被本模块清除（属 root 管理器/内核侧）
        printf 'kallsyms_ksu=%s\n' "$(awk '$3 ~ /^__?ksu_/ {c++} END{print c+0}' /proc/kallsyms 2>/dev/null)"
        printf 'kallsyms_susfs=%s\n' "$(awk '$3 ~ /^susfs_/ {c++} END{print c+0}' /proc/kallsyms 2>/dev/null)"
        # uname：可被 spoof_uname 改写，扫描器读 uname 时看不到真实串
        printf 'uname_release=%s\n' "$(cat /proc/sys/kernel/osrelease 2>/dev/null)"
        printf 'spoof_uname=%s\n' "$(cfg_get spoof_uname 0)"
        printf 'spoof_uname_value=%s\n' "$(cfg_get spoof_uname_release "")"
        # 隐藏面：sus_path 规则数、/data/adb 是否在小径表里
        printf 'sus_path_rules=%s\n' "$(grep -cvE '^\s*(#|$)' "$CONFIG/sus_path.txt" 2>/dev/null || echo 0)"
        if grep -qx "/data/adb" "$CONFIG/sus_path.txt" 2>/dev/null; then
            printf 'hides_data_adb=yes\n'
        else
            printf 'hides_data_adb=no\n'
        fi
        printf 'hide_kernelsu=%s\n' "$(hide_list_has kernelsu && echo 1 || echo 0)"
        printf 'note=%s\n' "kallsyms 计数属内核/root 管理器侧，本模块无法清除；netlink MAC/邻居泄漏属 ROM SELinux 策略"
        exit 0
        ;;
    guard_status)
        if autoload_paused; then
            echo "autoload=paused"
            if [ -f "$STATE/boot_guard" ]; then
                grep -E "^(kmi|at)=" "$STATE/boot_guard"
            fi
        else
            echo "autoload=ok"
        fi
        exit 0
        ;;
    list_kmis)
        . "$MODDIR/kmi.sh"
        list_kmis "$MODDIR"
        ;;
    loadstatus)
        _rel=$(cat /proc/sys/kernel/osrelease 2>/dev/null)
        echo "osrelease=$_rel"
        if susfs_kernel_ready; then
            echo "lkm=1"
            echo "kernel=$(susfs_kernel_kind)"
            echo "result=ok"
        else
            echo "lkm=0"
            if grep -q "load skip" "$MODDIR/load.log" 2>/dev/null; then
                echo "result=nomatch"
            elif grep -qE "susfs_insmod 失败|insmod .*失败|缺少 .* 的 LKM" "$MODDIR/load.log" 2>/dev/null; then
                echo "result=insmod_failed"
            else
                echo "result=not_loaded"
            fi
        fi
        echo "fail_count=$(cat "$STATE/fail_count" 2>/dev/null || echo 0)"
        _r=$(grep -E "未能匹配内核|susfs_insmod 失败|缺少 .* 的 LKM|无法读取内核版本|safe mode" "$MODDIR/load.log" 2>/dev/null | tail -1)
        echo "reason=$_r"
        _last=$(grep -n "=== SUSFS 管理器 load" "$MODDIR/load.log" 2>/dev/null | tail -1 | cut -d: -f1)
        if [ -n "$_last" ]; then
            echo "--- lastrun ---"
            tail -n +"$_last" "$MODDIR/load.log" | head -n 10
        fi
        ;;
    load)
        sh "$MODDIR/load.sh" manual
        _lrc=$?
        sh "$MODDIR/apply.sh"
        _arc=$?
        # 与 action.sh 一致：只有 apply 真正成功才清启动守卫，避免误清后不再提示
        case "$_arc" in
            0|5) [ "$_lrc" = "0" ] && susfs_kernel_ready && clear_boot_guard ;;
        esac
        if [ "$_lrc" != "0" ] || [ "$_arc" != "0" ]; then ( report_failure "manual_failed" >> "$STATE/stats.log" 2>&1 & ) 2>/dev/null || true; fi
        exit "$_arc"
        ;;
    apply)
        sh "$MODDIR/apply.sh"
        _arc=$?
        case "$_arc" in
            0|5) susfs_kernel_ready && clear_boot_guard ;;
        esac
        if [ "$_arc" != "0" ]; then ( report_failure "apply_failed" >> "$STATE/stats.log" 2>&1 & ) 2>/dev/null || true; fi
        exit "$_arc"
        ;;
    pid_guard_bundle)
        # PID 隐藏页一次性取回：配置（b64 一行）+ 7 个状态字段。
        # 不走完整 status：那里要算 kallsyms / 规则数 / 管理器探测，对这一个页面没必要。
        printf 'conf:'
        [ -f "$CONFIG/pid_guard.conf" ] && base64 < "$CONFIG/pid_guard.conf" 2>/dev/null | tr -d '\n'
        printf '\n'
        pg_status_fields
        ;;

    pid_guard_reload)
        # 只重载可选的 PID 隐藏组件：不碰 SUSFS 规则、不触发 LKM 加载。
        # KMI 必须用 select_kmi 现算（$KMI 只在 status() 内部赋值，这里为空会掉进
        # pid_guard.sh 的 uname -r 兜底，而 osrelease 可能已被本模块伪装）
        [ -f "$MODDIR/kmi.sh" ] && . "$MODDIR/kmi.sh"
        _pg_rel=$(real_kernel_release 2>/dev/null)
        _pg_kmi=$(select_kmi "$_pg_rel" "$MODDIR" 2>/dev/null)
        sh "$MODDIR/pid_guard.sh" "${_pg_kmi:-unknown}"
        _prc=$?
        echo "pid_guard_result=$(grep -m1 '^result=' "$STATE/pid_guard.status" 2>/dev/null | cut -d= -f2)"
        exit "$_prc"
        ;;
    allow_lkm)
        _cf_gate || { echo "文件与发布包不一致，拒绝执行"; exit 1; }
        mkdir -p "$CONFIG" 2>/dev/null
        date '+%F %T' > "$CONFIG/allow_lkm_on_kernelpatch" 2>/dev/null
        rm -f "$STATE/config_backup/allow_lkm_on_kernelpatch" 2>/dev/null
        if [ -f "$CONFIG/allow_lkm_on_kernelpatch" ]; then
            echo "allowed"
        else
            echo "failed"
            exit 1
        fi
        ;;
    disallow_lkm)
        _cf_gate || { echo "文件与发布包不一致，拒绝执行"; exit 1; }
        rm -f "$CONFIG/allow_lkm_on_kernelpatch" 2>/dev/null
        rm -f "$STATE/config_backup/allow_lkm_on_kernelpatch" 2>/dev/null
        echo "disallowed"
        ;;
    crash_ack)
        if pstore_crash_ack; then echo "acked"; else echo "failed"; exit 1; fi
        ;;
    crash_report)
        if pstore_crash_suspect; then echo "crash_suspect=yes"; else echo "crash_suspect=no"; fi
        _PCR=$(_pstore_dir)
        ls -l "$_PCR" 2>/dev/null | head -6
        [ -f "$STATE/crash_ack" ] && echo "acked=1"
        ;;
    backend_probe)
        _rel=$(cat /proc/sys/kernel/osrelease 2>/dev/null)
        echo "kernel=$_rel"
        if [ -f "$MODDIR/kmi.sh" ]; then
            . "$MODDIR/kmi.sh"
            echo "kmi=$(select_kmi "$_rel" "$MODDIR" 2>/dev/null)"
        fi
        echo "root_manager=$(ksu_branch 2>/dev/null)"
        echo "config_modules=$(kernel_config_get CONFIG_MODULES)"
        echo "config_kallsyms_all=$(kernel_config_get CONFIG_KALLSYMS_ALL)"
        echo "config_ksu=$(kernel_config_get CONFIG_KSU)"
        echo "config_ksu_susfs=$(kernel_config_get CONFIG_KSU_SUSFS)"
        echo "config_sus_path=$(kernel_config_get CONFIG_KSU_SUSFS_SUS_PATH)"
        echo "config_sus_mount=$(kernel_config_get CONFIG_KSU_SUSFS_SUS_MOUNT)"
        echo "config_sus_kstat=$(kernel_config_get CONFIG_KSU_SUSFS_SUS_KSTAT)"
        echo "config_open_redirect=$(kernel_config_get CONFIG_KSU_SUSFS_OPEN_REDIRECT)"
        echo "config_sus_map=$(kernel_config_get CONFIG_KSU_SUSFS_SUS_MAP)"
        if kernelpatch_present; then echo "apatch_userland=1"; else echo "apatch_userland=0"; fi
        echo "kernelpatch_kernel=$(kernelpatch_kernel_state)"
        echo "kernelpatch_version=$(kernelpatch_kernel_version)"
        _susfs_detect
        echo "susfs_kind=$_SUSFS_KIND"
        echo "proc_nodes=$(ls /proc/susfs_* 2>/dev/null | tr '\n' ' ')"
        _bp_bin=$(select_susfs_bin 2>/dev/null)
        echo "tool=${_bp_bin:-none}"
        if [ -n "$_bp_bin" ]; then
            echo "tool_version=$("$_bp_bin" show version 2>/dev/null)"
            echo "tool_variant=$("$_bp_bin" show variant 2>/dev/null)"
            echo "features:"
            "$_bp_bin" show enabled_features 2>/dev/null | sed 's/^/  /'
        fi
        echo "root_userland=$(ksu_branch 2>/dev/null)"
        echo "kernelpatch_runtime=$(kernelpatch_kernel_state)"
        echo "backend_kind=$_SUSFS_KIND"
        if [ "$_SUSFS_KIND" = "builtin" ]; then echo "backend_interface_detected=1"; else echo "backend_interface_detected=0"; fi
        echo "abi_match=unknown"
        echo "effect_verified=not_tested"
        _bp_ar=$(cat "$STATE/apply_result" 2>/dev/null)
        echo "apply_result=${_bp_ar:-not_tested}"
        echo "ksyms_ksu=$(awk '$3 ~ /^__?ksu_/ {c++} END{print c+0}' /proc/kallsyms 2>/dev/null)"
        echo "ksyms_susfs=$(awk '$3 ~ /^susfs_/ {c++} END{print c+0}' /proc/kallsyms 2>/dev/null)"
        if pstore_crash_suspect; then
            echo "crash_evidence=observed"
        elif _cr_fc2=$(pstore_crash_foreign) && [ -n "$_cr_fc2" ]; then
            echo "crash_evidence=foreign:$_cr_fc2"
        elif pstore_crash_unknown; then
            echo "crash_evidence=unknown"
        elif [ -d /sys/fs/pstore ]; then
            echo "crash_evidence=not_observed"
        else
            echo "crash_evidence=unavailable"
        fi
        ;;
    export_log)
        umask 077
        _outdir=/sdcard/Download
        [ -d "$_outdir" ] || _outdir=/data/local/tmp
        _out=$(mktemp "$_outdir/susfs_allinone-log-XXXXXX.txt" 2>/dev/null)
        [ -n "$_out" ] || _out="$_outdir/susfs_allinone-log-$$.txt"
        {
            echo "LKM SUSFS管理器 日志导出"
            echo "WARNING: 文件含隐藏路径、模块挂载点和 install_id；分享前请检查，用完建议删除。"
            echo "time=$(date '+%F %T' 2>/dev/null)"
            echo "module=$(get_prop version) / versionCode=$(get_prop versionCode)"
            echo "osrelease=$(cat /proc/sys/kernel/osrelease 2>/dev/null)"
            echo "manager=$(ksu_branch 2>/dev/null)"
            echo "===== status ====="
            sh "$MODDIR/ctl.sh" status 2>&1
            echo "===== load.log (tail 200) ====="
            tail -n 200 "$MODDIR/load.log" 2>/dev/null
            echo "===== apply.log (tail 300) ====="
            tail -n 300 "$MODDIR/apply.log" 2>/dev/null
        } > "$_out" 2>/dev/null
        if [ -s "$_out" ]; then
            chmod 600 "$_out" 2>/dev/null
            echo "$_out"
        else
            echo "export failed"
            exit 1
        fi
        ;;
    log)
        echo "===== load.log ====="
        tail -n 80 "$MODDIR/load.log" 2>/dev/null
        echo "===== apply.log ====="
        tail -n 120 "$MODDIR/apply.log" 2>/dev/null
        ;;
    clear_log)
        # WebUI 日志页的「清理」：把当前日志轮转成 .1（保留最后一轮便于回看），
        # 新日志从一行分隔头开始，避免直接清空后排查时什么线索都没有。
        _cl_n=0
        for _cl_f in load.log apply.log; do
            _cl_p="$MODDIR/$_cl_f"
            [ -f "$_cl_p" ] || continue
            _cl_sz=$(wc -c < "$_cl_p" 2>/dev/null)
            case "$_cl_sz" in ''|*[!0-9]*) _cl_sz=0 ;; esac
            [ "$_cl_sz" -gt 0 ] || continue
            mv -f "$_cl_p" "$_cl_p.1" 2>/dev/null || : > "$_cl_p" 2>/dev/null
            printf '=== %s 已被清理 %s（上一份保留为 %s.1）===\n' "$_cl_f" "$(now_stamp)" "$_cl_f" >> "$_cl_p" 2>/dev/null
            _cl_n=$((_cl_n + 1))
        done
        printf 'cleared=%s\n' "$_cl_n"
        ;;
    clear_logs)
        # 连 .1 备份一起删（用户明确要"全清"时用）
        _cls_n=0
        for _cls_f in "$MODDIR/load.log" "$MODDIR/apply.log" "$MODDIR/load.log.1" "$MODDIR/apply.log.1"; do
            [ -f "$_cls_f" ] || continue
            rm -f "$_cls_f" 2>/dev/null && _cls_n=$((_cls_n + 1))
        done
        printf 'removed=%s\n' "$_cls_n"
        ;;
    get_config)
        cat "$CONFIG/config.ini" 2>/dev/null
        ;;
    get_bundle)
        # 一次调用取回 config.ini + 7 个规则文件：WebUI 配置页原来要 8 次往返，
        # 每次都要经过 WebView 桥接 + 起一个 shell，加起来一两秒。
        # 输出：每行 name:b64（base64 去掉换行），顺序固定，缺文件给空串。
        _gb_emit() {
            printf '%s:' "$1"
            [ -f "$CONFIG/$2" ] && base64 < "$CONFIG/$2" 2>/dev/null | tr -d '\n'
            printf '\n'
        }
        _gb_emit config config.ini
        _gb_emit sus_path sus_path.txt
        _gb_emit sus_path_loop sus_path_loop.txt
        _gb_emit hide_modules hide_modules.txt
        _gb_emit skip_hide skip_hide.txt
        _gb_emit sus_mount sus_mount.txt
        _gb_emit try_umount try_umount.txt
        _gb_emit sus_map sus_map.txt
        ;;
    get_file)
        case "$2" in
            sus_path|sus_path_loop|sus_mount|try_umount|hide_modules|skip_hide|sus_map)
                cat "$CONFIG/$2.txt" 2>/dev/null
                ;;
            *)
                echo "unknown file"
                exit 1
                ;;
        esac
        ;;
    set_config)
        [ -n "$2" ] || { echo "empty config"; exit 1; }
        valid_b64 "$2" || { echo "invalid base64"; exit 1; }
        printf '%s' "$2" | base64 -d > "$CONFIG/config.ini.tmp" || { echo "decode failed"; exit 1; }
        if ! _err=$(validate_config_file "$CONFIG/config.ini.tmp"); then
            rm -f "$CONFIG/config.ini.tmp"
            echo "rejected: $_err"
            exit 1
        fi
        # 写配置与 apply 互斥：否则 apply 可能读到半截文件（mv 是原子的，但两处同时改会互相覆盖）
        if lock_acquire "$STATE/apply.lock" 30; then
            mv -f "$CONFIG/config.ini.tmp" "$CONFIG/config.ini"
            _sc_rc=$?
            # auto_load=0 要同步 disable_autoload，否则下次开机仍会自动加载
            _sc_auto=""
            while IFS= read -r _sc_l || [ -n "$_sc_l" ]; do
                case "$_sc_l" in auto_load=*) _sc_auto=${_sc_l#*=} ;; esac
            done < "$CONFIG/config.ini" 2>/dev/null
            case "$_sc_auto" in
                0) touch "$MODDIR/disable_autoload" 2>/dev/null ;;
                1) rm -f "$MODDIR/disable_autoload" 2>/dev/null ;;
            esac
            lock_release "$STATE/apply.lock"
        else
            _sc_rc=1
        fi
        [ "$_sc_rc" = "0" ] || { echo "busy"; exit 1; }
        echo "saved"
        ;;
    set_file)
        case "$2" in
            sus_path|sus_path_loop|sus_mount|try_umount|hide_modules|skip_hide|sus_map)
                ;;
            *)
                echo "unknown file"
                exit 1
                ;;
        esac
        b64="$3"
        if [ -n "$b64" ] && ! valid_b64 "$b64"; then
            echo "invalid base64"
            exit 1
        fi
        if [ -n "$b64" ]; then
            printf '%s' "$b64" | base64 -d > "$CONFIG/$2.txt.tmp" || { rm -f "$CONFIG/$2.txt.tmp"; echo "decode failed"; exit 1; }
        else
            : > "$CONFIG/$2.txt.tmp" || { rm -f "$CONFIG/$2.txt.tmp"; echo "write failed"; exit 1; }
        fi
        mv -f "$CONFIG/$2.txt.tmp" "$CONFIG/$2.txt"
        echo "saved"
        ;;
    set_bundle)
        # 和 apply 共用一把锁，避免写规则文件时被另一次 apply 读到半截
        lock_acquire "$STATE/apply.lock" 900 || { echo "apply busy"; exit 1; }
        trap 'lock_release "$STATE/apply.lock"' EXIT
        # 一次写入 config + 7 个规则文件（WebUI 保存从 8 次调用降到 1 次）。
        #
        # 线格式：外层 base64( 内层 ) ，内层为 8 段用 | 连接：
        #   段格式 v2（当前）：<解码后字节数>:<base64>
        #   段格式 v1（1.2.8 及更早）：<base64>
        # 带长度是为了能识别「base64 4 字符边界截断」——截断后仍是合法 base64，
        # 解出来只是内容前缀，重编码校验也一致，只有长度比对能发现。
        [ -n "$2" ] || { echo "empty bundle"; exit 1; }
        valid_b64 "$2" || { echo "invalid base64"; exit 1; }
        _raw=$(printf '%s' "$2" | base64 -d 2>/dev/null) || { echo "decode failed"; exit 1; }
        # 必须恰好 8 段：段数不对就把规则文件写空，不能接受
        _nsep=$(printf '%s' "$_raw" | tr -cd '|' | wc -c | tr -d ' ')
        if [ "$_nsep" != "7" ]; then
            echo "rejected: expect 8 segments, got $((_nsep + 1))"
            exit 1
        fi
        _dir="$CONFIG/.bundle.$$"
        rm -rf "$_dir"
        mkdir -p "$_dir" || { echo "tmp dir failed"; exit 1; }
        _names="config.ini sus_path.txt sus_path_loop.txt hide_modules.txt skip_hide.txt sus_mount.txt try_umount.txt sus_map.txt"
        _bad=""
        _idx=1
        for _n in $_names; do
            _seg=$(printf '%s' "$_raw" | cut -d'|' -f"$_idx")
            _idx=$((_idx + 1))
            # 段内长度前缀（v2）；没有前缀就按 v1 处理，兼容 1.2.8 客户端
            _expect=""
            case "$_seg" in
                *:*)
                    _head=${_seg%%:*}
                    case "$_head" in
                        ''|*[!0-9]*) ;;                       # 不是长度前缀，按 v1 处理
                        *) _expect=$_head; _seg=${_seg#*:} ;;
                    esac
                    ;;
            esac
            if ! printf '%s' "$_seg" | base64 -d > "$_dir/$_n" 2>/dev/null; then
                _bad="decode $_n"
                break
            fi
            # toybox 的 base64 -d 对非法输入也返回 0：非空段解出 0 字节必然有问题
            if [ -n "$_seg" ] && [ ! -s "$_dir/$_n" ]; then
                _bad="decode $_n (空输出)"
                break
            fi
            if [ -n "$_expect" ]; then
                _got=$(wc -c < "$_dir/$_n" | tr -d ' ')
                if [ "$_got" != "$_expect" ]; then
                    _bad="decode $_n (长度不符：期望 $_expect，实际 $_got)"
                    break
                fi
            elif [ -n "$_seg" ]; then
                # v1 无法做长度校验，退化为重编码比对（能拦住非法/半截编码）
                _reenc=$(base64 < "$_dir/$_n" 2>/dev/null | tr -d '\n')
                _orig=$(printf '%s' "$_seg" | tr -d '\n')
                if [ "$_reenc" != "$_orig" ]; then
                    _bad="decode $_n (内容不完整)"
                    break
                fi
            fi
        done
        if [ -z "$_bad" ] && [ ! -s "$_dir/config.ini" ]; then
            # 0 字节 config.ini 不可能是有意保存的结果，直接拒绝（旧的 validate 会放行空文件）
            _bad="config.ini 为空"
        fi
        if [ -z "$_bad" ]; then
            _err=$(validate_config_file "$_dir/config.ini") || _bad="config: $_err"
        fi
        if [ -n "$_bad" ]; then
            rm -rf "$_dir"
            echo "rejected: $_bad"
            exit 1
        fi
        _old="$CONFIG/.bundle.old.$$"
        rm -rf "$_old"; mkdir -p "$_old" 2>/dev/null || { rm -rf "$_dir"; echo "tmp dir failed"; exit 1; }
        for _n in $_names; do [ -f "$CONFIG/$_n" ] && cp -f "$CONFIG/$_n" "$_old/$_n" 2>/dev/null; done
        _moved=""
        for _n in $_names; do
            if mv -f "$_dir/$_n" "$CONFIG/$_n" 2>/dev/null; then
                _moved="$_moved $_n"
            else
                for _r in $_moved; do
                    if [ -f "$_old/$_r" ]; then
                        cp -f "$_old/$_r" "$CONFIG/$_r" 2>/dev/null
                    else
                        # 失败前新建的文件没有旧备份，回滚时要删除，不能留下半套配置
                        rm -f "$CONFIG/$_r" 2>/dev/null
                    fi
                done
                rm -rf "$_dir" "$_old"
                echo "write failed: $_n"
                exit 1
            fi
        done
        rm -rf "$_dir" "$_old"
        # 同步自动加载标记（load.sh 会检查 disable_autoload）
        _al=$(grep '^auto_load=' "$CONFIG/config.ini" 2>/dev/null | tail -1 | cut -d= -f2)
        case "$_al" in
            0) touch "$MODDIR/disable_autoload" 2>/dev/null ;;
            1) rm -f "$MODDIR/disable_autoload" 2>/dev/null ;;
        esac
        echo "saved"
        ;;
    set_stats)
        # 关于页的匿名统计开关：单独入口，切换即生效（无需再点「保存并应用」）
        case "${2:-}" in 0|1) ;; *) echo "bad value"; exit 1 ;; esac
        mkdir -p "$CONFIG" 2>/dev/null
        _ss="$CONFIG/config.ini"
        cfg_ensure 2>/dev/null
        [ -f "$_ss" ] || : > "$_ss"
        sed -i "/^anonymous_stats=/d" "$_ss" 2>/dev/null
        # 末行没有换行符时先补一个，否则新键会黏到上一行（config.ini 可能被手改过）
        if [ -s "$_ss" ] && [ -n "$(tail -c 1 "$_ss" 2>/dev/null)" ]; then
            printf '\n' >> "$_ss" 2>/dev/null
        fi
        printf 'anonymous_stats=%s\n' "$2" >> "$_ss" 2>/dev/null || { echo "write failed"; exit 1; }
        if [ "$2" = "0" ]; then
            # 关闭立即撤销本地 token，之后不再请求
            rm -f "$(stats_token_file)" 2>/dev/null
        else
            # setsid 脱离当前会话，避免父 shell 退出时被 SIGHUP 打断（实测会 Hangup）
            if [ -x /system/bin/setsid ]; then
                setsid sh "$MODDIR/ctl.sh" report_install >> "$STATE/stats.log" 2>&1 &
            else
                ( report_install >> "$STATE/stats.log" 2>&1 & ) 2>/dev/null || true
            fi
        fi
        echo "saved"
        ;;
    set_flag)
        # 白名单标记位，写入 state 下的独立文件（不进 config.ini，避免被通用写入器绕过）
        case "$2" in
            force_bl_unlocked) ;;
            *) echo "unknown flag"; exit 1 ;;
        esac
        case "$3" in
            0|1) ;;
            *) echo "bad value"; exit 1 ;;
        esac
        # 写入独立标记文件，而不是 config.ini：
        # 这样 set_config / set_bundle 这类通用配置写入器无法绕过前端的强制确认
        set_force_bl "$3"
        # 清理旧版写在 config.ini 里的同键，避免两处取值不一致
        if [ -f "$CONFIG/config.ini" ]; then
            sed -i "/^$2=/d" "$CONFIG/config.ini" 2>/dev/null
        fi
        echo "saved"
        ;;
    set_auto)
        case "$2" in
            0|1) ;;
            *) echo "bad value"; exit 1 ;;
        esac
        if [ -f "$CONFIG/config.ini" ]; then
            if grep -q '^auto_load=' "$CONFIG/config.ini"; then
                sed -i "s/^auto_load=.*/auto_load=$2/" "$CONFIG/config.ini"
            else
                [ -n "$(tail -c1 "$CONFIG/config.ini" 2>/dev/null)" ] && printf '\n' >> "$CONFIG/config.ini"
                printf 'auto_load=%s\n' "$2" >> "$CONFIG/config.ini"
            fi
        else
            printf 'auto_load=%s\n' "$2" > "$CONFIG/config.ini"
        fi
        if [ "$2" = "1" ]; then
            rm -f "$MODDIR/disable_autoload"
        else
            touch "$MODDIR/disable_autoload"
        fi
        echo "saved"
        ;;
    import_legacy)
        LEGACY=/data/adb/susfs4ksu
        if [ ! -d "$LEGACY" ]; then
            echo "legacy config not found"
            exit 1
        fi
        for f in sus_path sus_mount try_umount; do
            [ -f "$LEGACY/$f.txt" ] || continue
            _tmp="$CONFIG/$f.txt.import.$$"
            if cp -f "$LEGACY/$f.txt" "$_tmp" 2>/dev/null && mv -f "$_tmp" "$CONFIG/$f.txt" 2>/dev/null; then
                :
            else
                rm -f "$_tmp"
                echo "import failed: $f"
                exit 1
            fi
        done
        # 只在为空时补默认值，避免覆盖用户自定义的隐藏模块列表
        if [ ! -s "$CONFIG/hide_modules.txt" ]; then
            printf 'kernelsu\n' > "$CONFIG/hide_modules.txt.tmp.$$" && mv -f "$CONFIG/hide_modules.txt.tmp.$$" "$CONFIG/hide_modules.txt"
        fi
        echo "imported"
        ;;
    reset_defaults)
        # 这是「毁灭性」操作：先把现有 8 个文件备份到 config.bak.<时间戳>/，
        # 每步写入都检查返回值，任何一步失败就报 failed 并保留备份（audit M2）
        _rd_stamp=$(date +%Y%m%d-%H%M%S 2>/dev/null)
        case "$_rd_stamp" in ''|*[!0-9-]*) _rd_stamp=manual ;; esac
        _rd_bak="$MODDIR/config.bak.$_rd_stamp"
        _rd_ok=1
        mkdir -p "$_rd_bak" 2>/dev/null || _rd_ok=0
        if [ "$_rd_ok" = "1" ]; then
            for _rd_f in config.ini sus_path.txt sus_path_loop.txt sus_mount.txt \
                         try_umount.txt hide_modules.txt skip_hide.txt sus_map.txt; do
                [ -f "$CONFIG/$_rd_f" ] || continue
                cp -f "$CONFIG/$_rd_f" "$_rd_bak/$_rd_f" 2>/dev/null || _rd_ok=0
            done
        fi
        # 备份失败就别动原文件
        if [ "$_rd_ok" != "1" ]; then
            rm -rf "$_rd_bak" 2>/dev/null
            echo "failed: backup"
            exit 1
        fi

        _rd_write() {
            # $1=目标文件，内容走 stdin
            _rd_tmp="$1.tmp.$$"
            cat > "$_rd_tmp" 2>/dev/null || { rm -f "$_rd_tmp" 2>/dev/null; return 1; }
            mv -f "$_rd_tmp" "$1" 2>/dev/null || { rm -f "$_rd_tmp" 2>/dev/null; return 1; }
            return 0
        }

        _rd_write "$CONFIG/sus_map.txt" <<'EOF' || _rd_ok=0
# 每行一个文件路径
EOF
        _rd_write "$CONFIG/skip_hide.txt" <<'EOF' || _rd_ok=0
# 每行一个包名子串，命中则不隐藏其数据目录
duckdetector
appvisibility
nativecheck
EOF
        _rd_write "$CONFIG/config.ini" <<'EOF' || _rd_ok=0
# SUSFS 管理器配置
auto_load=1
hide_sus_mnts=1
anonymous_stats=1
avc_spoof=1
replace_rules=0
hide_ksu_loop=0
hide_revanced=0
hide_custom_rom=0
hide_compat_matrix=0
hide_gapps=0
hide_dex2oat=0
hide_scene=0
auto_try_umount=0
skip_legit_mounts=1
skip_detection_paths=1
fake_cmdline=0
fake_cmdline_value=
force_kmi=
manager_name=
hide_vendor_sepolicy=0
vold_isolation=0
spoof_uname=0
spoof_uname_release=
spoof_uname_version=
EOF
        _rd_write "$CONFIG/sus_path.txt" <<'EOF' || _rd_ok=0
# 每行一个要隐藏的路径，支持以 # 开头的注释
# 隐藏 /data/adb 后，SukiSU 和本模块 WebUI 仍可正常使用
/data/adb
EOF
        _rd_write "$CONFIG/hide_modules.txt" <<'EOF' || _rd_ok=0
# 每行一个模块名，写入 /proc/susfs_hide_modules
kernelsu
EOF
        _rd_write "$CONFIG/sus_path_loop.txt" <<'EOF' || _rd_ok=0
# 每行一个路径；路径可以暂时不存在，内核会在它出现后解析并隐藏
# 适合会被删除后重建的路径；静态路径请继续放 sus_path.txt
EOF
        _rd_write "$CONFIG/sus_mount.txt" <<'EOF' || _rd_ok=0
# 每行一个挂载点，调用 ksu_susfs add_sus_mount
EOF
        _rd_write "$CONFIG/try_umount.txt" <<'EOF' || _rd_ok=0
# 每行一个路径，调用 ksu_susfs add_try_umount <path> 1
EOF

        if [ "$_rd_ok" != "1" ]; then
            # 有文件写失败：备份还在，提示用户从备份恢复
            echo "failed: write (备份在 $(basename "$_rd_bak"))"
            exit 1
        fi
        rm -f "$MODDIR/disable_autoload"
        echo "reset"
        echo "backup=$_rd_bak"
        ;;
    *)
        echo "unknown command: $1"
        exit 1
        ;;
esac