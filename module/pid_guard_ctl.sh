#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# 读/写 config/pid_guard.conf。写入前先校验：pid_guard.sh 只按固定键解析该文件、
# 不 source，这里挡在入口，避免把空格、裸 *、shell 元字符写进配置。
# 无路径调用（sh pid_guard.sh）时 ${0%/*} 会退化成脚本名，这里兜底到模块目录
case "$0" in
    */*) MODDIR=${0%/*} ;;
    *) MODDIR=/data/adb/modules/susfs_allinone ;;
esac
CONF="$MODDIR/config/pid_guard.conf"
get() { cat "$CONF" 2>/dev/null; }

# 允许字符：字母数字与 _,.:/@+- ；comm 额外允许 * 但只能作后缀
value_ok() {
    case "$1" in
        *[!A-Za-z0-9_,.:/@+*-]*) return 1 ;;
        *,|,*|*,,*|*" "*) return 1 ;;
    esac
    return 0
}

# UID 只接受数字或数字-数字
uids_ok() {
    [ -n "$1" ] || return 0
    _r=$1
    while :; do
        case "$_r" in
            *,*) _t=${_r%%,*}; _r=${_r#*,} ;;
            *) _t=$_r; _r="" ;;
        esac
        case "$_t" in
            ''|*[!0-9-]*|*-*-*|-*|*-) return 1 ;;
        esac
        [ -n "$_r" ] || break
    done
    return 0
}

# comm 通配只允许"尾部一个 *"（前缀匹配）；中间/开头/多个 * 会匹配到几乎全部进程，
# 等于把整个系统藏起来，直接拒绝（audit-legacy m7）
comms_wildcard_ok() {
    [ -n "$1" ] || return 0
    _cw_r=$1
    while :; do
        case "$_cw_r" in
            *,*) _cw_t=${_cw_r%%,*}; _cw_r=${_cw_r#*,} ;;
            *) _cw_t=$_cw_r; _cw_r="" ;;
        esac
        case "$_cw_t" in
            *'*'*)
                # 去掉尾部一个 * 后不允许再出现 *
                _cw_rest=${_cw_t%'*'}
                case "$_cw_rest" in
                    ''|*'*'*) return 1 ;;
                esac
                ;;
        esac
        [ -n "$_cw_r" ] || break
    done
    return 0
}

fail() { echo "rejected: $1" >&2; exit 1; }

validate() {
    _v_en=$(grep -m1 '^enabled=' "$1" 2>/dev/null | cut -d= -f2-)
    _v_uids=$(grep -m1 '^target_uids=' "$1" 2>/dev/null | cut -d= -f2-)
    _v_comms=$(grep -m1 '^target_comms=' "$1" 2>/dev/null | cut -d= -f2-)
    _v_exc=$(grep -m1 '^exclude_comms=' "$1" 2>/dev/null | cut -d= -f2-)
    [ -n "$_v_en" ] || fail "missing enabled"
    case "$_v_en" in 0|1) ;; *) fail "enabled must be 0 or 1" ;; esac
    value_ok "$_v_uids"  || fail "target_uids illegal char / empty item / space"
    uids_ok "$_v_uids"   || fail "target_uids must be digits or digits-digits"
    value_ok "$_v_comms" || fail "target_comms illegal char / empty item / space"
    value_ok "$_v_exc"   || fail "exclude_comms illegal char / empty item / space"
    [ -n "$_v_uids$_v_comms" ] || fail "target_uids and target_comms cannot both be empty"
    case "$_v_uids$_v_exc" in *'*'*) fail "wildcard * not allowed in uid/exclude" ;; esac
    comms_wildcard_ok "$_v_comms" || fail "comm wildcard * only allowed as a trailing *"
    case ",$_v_comms," in
        *",*,"*|*",**,"*) fail "comm wildcard * must be a suffix; bare * hits every process" ;;
    esac
}

set_b64() {
    [ -n "${2:-}" ] || { echo "missing payload" >&2; exit 1; }
    tmp="$CONF.tmp.$$"
    printf '%s' "$2" | base64 -d > "$tmp" || { rm -f "$tmp"; exit 1; }
    validate "$tmp" || { rm -f "$tmp"; exit 1; }
    chmod 600 "$tmp"
    mkdir -p "$MODDIR/config" 2>/dev/null
    mv -f "$tmp" "$CONF" || { rm -f "$tmp"; exit 1; }
    echo saved
}

case "${1:-get}" in
    get) get ;;
    set_b64) set_b64 "$@" ;;
    *) echo "unknown" >&2; exit 1 ;;
esac
