#!/system/bin/sh
# WebUI 后端：只接受白名单命令，所有操作以 root 身份执行。
MODDIR=/data/adb/modules/susfs_allinone
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
    REL=$(cat /proc/sys/kernel/osrelease 2>/dev/null)
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
    [ -f "$CONFIG/config.sh" ] && . "$CONFIG/config.sh" 2>/dev/null
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
        cat "$CONFIG/config.sh" 2>/dev/null
        ;;
    get_file)
        case "$2" in
            sus_path|sus_mount|try_umount|hide_modules)
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
        printf '%s' "$2" | base64 -d > "$CONFIG/config.sh.tmp" || { echo "decode failed"; exit 1; }
        # 拒绝可疑内容：配置会被 root shell source，禁止命令替换与分隔符
        if grep -qE '[$`]|;|&&|\|\|' "$CONFIG/config.sh.tmp" 2>/dev/null; then
            rm -f "$CONFIG/config.sh.tmp"
            echo "rejected: unsafe characters in config"
            exit 1
        fi
        mv -f "$CONFIG/config.sh.tmp" "$CONFIG/config.sh"
        echo "saved"
        ;;
    set_file)
        case "$2" in
            sus_path|sus_mount|try_umount|hide_modules)
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
    set_auto)
        case "$2" in
            0|1) ;;
            *) echo "bad value"; exit 1 ;;
        esac
        if [ -f "$CONFIG/config.sh" ]; then
            if grep -q '^auto_load=' "$CONFIG/config.sh"; then
                sed -i "s/^auto_load=.*/auto_load=$2/" "$CONFIG/config.sh"
            else
                printf 'auto_load=%s\n' "$2" >> "$CONFIG/config.sh"
            fi
        else
            printf 'auto_load=%s\n' "$2" > "$CONFIG/config.sh"
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
        echo "kernelsu" > "$CONFIG/hide_modules.txt"
        echo "imported"
        ;;
    reset_defaults)
        cat > "$CONFIG/config.sh" <<'EOF'
# SUSFS 管理器配置
auto_load=1
hide_sus_mnts=1
avc_spoof=0
replace_rules=1
hide_ksu_loop=0
hide_revanced=0
hide_custom_rom=0
hide_compat_matrix=0
fake_cmdline=0
fake_cmdline_value=
force_kmi=
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
