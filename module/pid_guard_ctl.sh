#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# 读/写 config/pid_guard.conf。写入前先校验：pid_guard.sh 只按固定键解析该文件、
# 不 source，这里挡在入口，避免把空格、裸 *、shell 元字符写进配置。
MODDIR=${0%/*}
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

fail() { echo "rejected: $1" >&2; exit 1; }

validate() {
    _v_en=$(grep -m1 '^enabled=' "$1" 2>/dev/null | cut -d= -f2-)
    _v_uids=$(grep -m1 '^target_uids=' "$1" 2>/dev/null | cut -d= -f2-)
    _v_comms=$(grep -m1 '^target_comms=' "$1" 2>/dev/null | cut -d= -f2-)
    _v_exc=$(grep -m1 '^exclude_comms=' "$1" 2>/dev/null | cut -d= -f2-)
    [ -n "$_v_en" ] || fail "missing enabled"
    case "$_v_en" in 0|1) ;; *) fail "enabled must be 0 or 1" ;; esac
    value_ok "$_v_uids"  || fail "target_uids illegal char / empty item / space"
    value_ok "$_v_comms" || fail "target_comms illegal char / empty item / space"
    value_ok "$_v_exc"   || fail "exclude_comms illegal char / empty item / space"
    case "$_v_uids$_v_exc" in *'*'*) fail "wildcard * not allowed in uid/exclude" ;; esac
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
