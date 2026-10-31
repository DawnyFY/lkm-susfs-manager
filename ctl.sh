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

status() {
    REL=$(real_kernel_release 2>/dev/null)
    [ -n "$REL" ] || REL=$(cat /proc/sys/kernel/osrelease 2>/dev/null)
    KMI=unknown
    if [ -f "$MODDIR/kmi.sh" ] && [ -n "$REL" ]; then
        . "$MODDIR/kmi.sh"
        KMI=$(select_kmi "$REL" "$MODDIR" 2>/dev/null) || KMI=unknown
    fi

    PRESENT=0
    lkm_present && PRESENT=1
    BIN=$(select_susfs_bin 2>/dev/null)

    VARIANT=""
    VERSION=""
    if [ "$PRESENT" = "1" ] && [ -n "$BIN" ]; then
        VARIANT=$("$BIN" show variant 2>/dev/null)
        VERSION=$("$BIN" show version 2>/dev/null)
    fi

    RULES=$(grep '^path=' /proc/susfs_path 2>/dev/null | grep -v '\[ours:' | sed 's/^path=//' | awk '{print $1}' | sort -u | wc -l | tr -d ' ')
    RULES=${RULES:-0}
    HIDE=0
    grep -qw kernelsu /proc/susfs_hide_modules 2>/dev/null && HIDE=1
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
            if "$BIN" show version >/dev/null 2>&1; then
                KSSTAT=ok
            else
                KSSTAT=incompatible
            fi
        else
            KSSTAT=ok
        fi
    fi
    FAILS=$(cat "$MODDIR/state/fail_count" 2>/dev/null)
    FAILS=${FAILS:-0}
    LSIZE=$(stat -c %s "$MODDIR/lib/susfs_guard_lkm-$KMI.ko" 2>/dev/null)
    LSIZE=${LSIZE:-0}

    printf 'module_version=%s\n' "$(get_prop version)"
    printf 'description=%s\n' "$(get_prop description)"
    printf 'kernel=%s\n' "$REL"
    printf 'kmi=%s\n' "$KMI"
    printf 'lkm_present=%s\n' "$PRESENT"
    printf 'lkm_variant=%s\n' "$VARIANT"
    printf 'lkm_version=%s\n' "$VERSION"
    printf 'rules=%s\n' "$RULES"
    printf 'hide_kernelsu=%s\n' "$HIDE"
    printf 'marker=%s\n' "$MARKER"
    printf 'auto_load=%s\n' "$AUTOLOAD"
    printf 'root_manager=%s\n' "$(ksu_branch)"
    printf 'ksu_bin=%s\n' "$KSSTAT"
    printf 'ksu_bin_path=%s\n' "$BIN"
    printf 'selinux=%s\n' "$(getenforce 2>/dev/null)"
    printf 'fail_count=%s\n' "$FAILS"
    printf 'lkm_size=%s\n' "$LSIZE"
    if autoload_paused; then printf 'autoload=paused\n'; else printf 'autoload=ok\n'; fi
    if cap_ok sus_mount; then printf 'sus_mount=ok\n'; else printf 'sus_mount=unsupported\n'; fi
    if cap_ok try_umount; then printf 'try_umount=ok\n'; else printf 'try_umount=unsupported\n'; fi
    printf 'bootloader=%s\n' "$(bootloader_state)"
    printf 'force_bl_unlocked=%s\n' "$(cfg_force_bl)"
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
        case "$_val" in
            *[[:space:]]*) _bad="line $_ln: whitespace in value"; break ;;
            *\"*|*"'"*|*\\*) _bad="line $_ln: quote or backslash in value"; break ;;
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
        # 立即重扫 /dev 下的 Scene 痕迹目录（名字随机，按内容特征识别）
        BIN=$(select_susfs_bin 2>/dev/null) || { echo "no ksu_susfs"; exit 1; }
        _n=0
        for _f in /dev/*/scene_mode_category; do
            [ -e "$_f" ] || continue
            _d=${_f%/scene_mode_category}
            if "$BIN" add_sus_path "$_d" >/dev/null 2>&1; then
                record_our_path "$_d"
                echo "hidden $_d"
                _n=$((_n + 1))
            else
                echo "exists $_d"
            fi
            "$BIN" add_sus_path "$_f" >/dev/null 2>&1 && record_our_path "$_f"
        done
        if [ "$_n" = "0" ]; then
            echo "none"
        fi
        exit 0
        ;;
    preset_paths)
        # 输出当前设备上真实存在的建议隐藏路径（已配置的由前端标记，不在此过滤）
        _cur="$CONFIG/sus_path.txt"
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
                  /data/local/tmp/mount_mask /data/local/tmp/mount_mark; do
            if [ -e "$_p" ]; then
                printf '%s\t1\n' "$_p"
            else
                printf '%s\t0\n' "$_p"
            fi
        done
        # Scene 痕迹目录名随机，不放进预设（用「隐藏 Scene 痕迹」开关 + 重扫处理）
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
        if lkm_present; then
            echo "lkm=1"
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
        sh "$MODDIR/apply.sh"
        ;;
    apply)
        sh "$MODDIR/apply.sh"
        ;;
    log)
        echo "===== load.log ====="
        tail -n 80 "$MODDIR/load.log" 2>/dev/null
        echo "===== apply.log ====="
        tail -n 120 "$MODDIR/apply.log" 2>/dev/null
        ;;
    get_config)
        cat "$CONFIG/config.ini" 2>/dev/null
        ;;
    get_file)
        case "$2" in
            sus_path|sus_mount|try_umount|hide_modules|skip_hide)
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
        mv -f "$CONFIG/config.ini.tmp" "$CONFIG/config.ini"
        echo "saved"
        ;;
    set_file)
        case "$2" in
            sus_path|sus_mount|try_umount|hide_modules|skip_hide)
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
            printf '%s' "$b64" | base64 -d > "$CONFIG/$2.txt.tmp" || { echo "decode failed"; exit 1; }
        else
            : > "$CONFIG/$2.txt.tmp" || { echo "write failed"; exit 1; }
        fi
        mv -f "$CONFIG/$2.txt.tmp" "$CONFIG/$2.txt"
        echo "saved"
        ;;
    set_bundle)
        # 一次写入 config + 5 个规则文件：WebUI 保存从 6 次调用降到 1 次，
        # 避免开机 apply 读到「新配置 + 旧规则文件」的中间状态。
        # 参数：base64( "b64(config)|b64(sus_path)|b64(hide_modules)|b64(skip_hide)|b64(sus_mount)|b64(try_umount)" )
        [ -n "$2" ] || { echo "empty bundle"; exit 1; }
        valid_b64 "$2" || { echo "invalid base64"; exit 1; }
        _raw=$(printf '%s' "$2" | base64 -d 2>/dev/null) || { echo "decode failed"; exit 1; }
        # 必须恰好 6 段：段数不对就把规则文件写空，不能接受
        _nsep=$(printf '%s' "$_raw" | tr -cd '|' | wc -c | tr -d ' ')
        if [ "$_nsep" != "5" ]; then
            echo "rejected: expect 6 segments, got $((_nsep + 1))"
            exit 1
        fi
        _dir="$CONFIG/.bundle.$$"
        rm -rf "$_dir"
        mkdir -p "$_dir" || { echo "tmp dir failed"; exit 1; }
        _names="config.ini sus_path.txt hide_modules.txt skip_hide.txt sus_mount.txt try_umount.txt"
        _bad=""
        _idx=1
        for _n in $_names; do
            # 用 cut 按 | 取段：mksh 下 ${var%%|*} 的模式解析不一致，cut 更稳
            _seg=$(printf '%s' "$_raw" | cut -d'|' -f"$_idx")
            _idx=$((_idx + 1))
            if ! printf '%s' "$_seg" | base64 -d > "$_dir/$_n" 2>/dev/null; then
                _bad="decode $_n"
                break
            fi
        done
        if [ -z "$_bad" ]; then
            _err=$(validate_config_file "$_dir/config.ini") || _bad="config: $_err"
        fi
        if [ -n "$_bad" ]; then
            rm -rf "$_dir"
            echo "rejected: $_bad"
            exit 1
        fi
        for _n in $_names; do
            if ! mv -f "$_dir/$_n" "$CONFIG/$_n" 2>/dev/null; then
                rm -rf "$_dir"
                echo "write failed: $_n"
                exit 1
            fi
        done
        rm -rf "$_dir"
        # 同步自动加载标记（load.sh 会检查 disable_autoload）
        _al=$(grep '^auto_load=' "$CONFIG/config.ini" 2>/dev/null | tail -1 | cut -d= -f2)
        case "$_al" in
            0) touch "$MODDIR/disable_autoload" 2>/dev/null ;;
            1) rm -f "$MODDIR/disable_autoload" 2>/dev/null ;;
        esac
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
            [ -f "$LEGACY/$f.txt" ] && cp -f "$LEGACY/$f.txt" "$CONFIG/$f.txt"
        done
        # 只在为空时补默认值，避免覆盖用户自定义的隐藏模块列表
        if [ ! -s "$CONFIG/hide_modules.txt" ]; then
            echo "kernelsu" > "$CONFIG/hide_modules.txt"
        fi
        echo "imported"
        ;;
    reset_defaults)
        cat > "$CONFIG/config.ini" <<'EOF'
# SUSFS 管理器配置
auto_load=1
hide_sus_mnts=1
avc_spoof=0
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
force_bl_unlocked=0
spoof_uname=0
spoof_uname_release=
spoof_uname_version=
EOF
        cat > "$CONFIG/sus_path.txt" <<'EOF'
# 每行一个要隐藏的路径，支持以 # 开头的注释
# 隐藏 /data/adb 后，SukiSU 和本模块 WebUI 仍可正常使用
/data/adb
EOF
        cat > "$CONFIG/hide_modules.txt" <<'EOF'
# 每行一个模块名，写入 /proc/susfs_hide_modules
kernelsu
EOF
        cat > "$CONFIG/sus_mount.txt" <<'EOF'
# 每行一个挂载点，调用 ksu_susfs add_sus_mount
EOF
        cat > "$CONFIG/try_umount.txt" <<'EOF'
# 每行一个路径，调用 ksu_susfs add_try_umount <path> 1
EOF
        rm -f "$MODDIR/disable_autoload"
        echo "reset"
        ;;
    *)
        echo "unknown command: $1"
        exit 1
        ;;
esac