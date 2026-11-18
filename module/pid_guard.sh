#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Optional PID guard bundled with the SUSFS manager.
# $1 is the KMI selected by load.sh (e.g. android15-6.6); do not guess.
# 幂等：enabled=1 且已加载时只补隐藏；enabled=0 时主动卸载（不必重启）。
# 本脚本的失败只写 state/pid_guard.status 与 load.log，不动 state/fail_count：
# 可选的 PID 隐藏失败不应该触发 SUSFS 自动加载暂停。
MODDIR=${0%/*}
MODNAME=generic_pid_guard
CONF="$MODDIR/config/pid_guard.conf"
STATE="$MODDIR/state"
LOG="$MODDIR/load.log"
# 设备默认路径；PG_* 只是离线测试替换缝，设备上不会设置
SYS_MOD=${PG_SYS_MOD:-/sys/module}
PROC_MODULES=${PG_PROC_MODULES:-/proc/modules}
HIDE_LIST=${PG_HIDE_LIST:-/proc/susfs_hide_modules}
KSUD=${PG_KSUD:-/data/adb/ksu/bin/ksud}

mkdir -p "$STATE" 2>/dev/null

log() { echo "$1" >> "$LOG"; }
loaded() { [ -d "$SYS_MOD/$MODNAME" ]; }
conf_hash() { cksum "$CONF" 2>/dev/null | awk '{print $1 "-" $2}'; }

write_status() {
    {
        echo "result=$1"
        echo "kmi=${2:-}"
        echo "short=${3:-}"
        echo "rc=${4:-0}"
        echo "ts=$(date '+%F %T')"
    } > "$STATE/pid_guard.status" 2>/dev/null
}

# /proc/modules 里可见时补一条隐藏，与 hide_modules.txt 同一条内核接口
hide_self() {
    [ -e "$HIDE_LIST" ] || return 0
    grep -qw "$MODNAME" "$HIDE_LIST" 2>/dev/null && return 0
    if echo "add $MODNAME" > "$HIDE_LIST" 2>/dev/null; then
        log "[+] hide_module $MODNAME"
    else
        log "[=] hide_module $MODNAME (失败)"
    fi
}

unhide_self() {
    [ -e "$HIDE_LIST" ] || return 0
    grep -qw "$MODNAME" "$HIDE_LIST" 2>/dev/null || return 0
    echo "del $MODNAME" > "$HIDE_LIST" 2>/dev/null && log "[-] hide_module $MODNAME 已移除"
}

unload() {
    loaded || { log "[=] pid_guard 未加载，无需卸载"; write_status skipped "" "" 0; return 0; }
    if command -v rmmod >/dev/null 2>&1 && rmmod "$MODNAME" >/dev/null 2>&1; then
        log "[-] pid_guard 已卸载（rmmod）"
        rm -f "$STATE/pid_guard.conf_hash" 2>/dev/null
        unhide_self
        write_status unloaded
        return 0
    fi
    if [ -x "$KSUD" ] && "$KSUD" rmmod "$MODNAME" >/dev/null 2>&1; then
        log "[-] pid_guard 已卸载（ksud rmmod）"
        rm -f "$STATE/pid_guard.conf_hash" 2>/dev/null
        unhide_self
        write_status unloaded
        return 0
    fi
    log "[!] pid_guard 卸载失败（enabled=0 但模块仍驻留，重启后不再加载）"
    write_status unload_failed "" "" 1
    return 1
}

# 配置只按固定键读取，**绝不 source**：
# 历史实现 `. "$CONF"` 会把 $(...)/; 当 shell 执行（root），且值里一个空格就按 POSIX
# 赋值规则把整个字段截断成空——insmod 仍成功、状态仍 ok，功能静默消失。
conf_get() { grep -m1 "^$1=" "$CONF" 2>/dev/null | cut -d= -f2-; }

pg_reject() {
    log "[!] pid_guard 配置被拒绝：$1（本次不加载，修好保存后自动重试）"
    write_status bad_conf "" "" 2
    exit 0
}

# 允许字符：字母数字与 _,.:/@+- ；comm 额外允许 * 但只能作后缀
pg_value_ok() {
    case "$1" in
        *[!A-Za-z0-9_,.:/@+*-]*) return 1 ;;
        *,|,*|*,,*|*" "*) return 1 ;;
    esac
    return 0
}

[ -f "$CONF" ] || exit 0

ENABLED=$(conf_get enabled)
UIDS=$(conf_get target_uids)
COMMS=$(conf_get target_comms)
EXCLUDES=$(conf_get exclude_comms)
case "$ENABLED" in 1) ;; *) ENABLED=0 ;; esac

pg_value_ok "$UIDS"     || pg_reject "target_uids 含非法字符/空项/空格"
pg_value_ok "$COMMS"    || pg_reject "target_comms 含非法字符/空项/空格"
pg_value_ok "$EXCLUDES" || pg_reject "exclude_comms 含非法字符/空项/空格"
case "$UIDS$EXCLUDES" in *'*'*) pg_reject "UID/排除项不允许 *" ;; esac
case ",$COMMS," in
    *",*,"*|*",**,"*) pg_reject "目标 comm 的 * 只能作后缀，不能是裸 *" ;;
esac

if [ "$ENABLED" != "1" ]; then
    unload || exit 1
    exit 0
fi

KMI_FULL=${1:-}
SHORT=""
case "$KMI_FULL" in
    android12-5.10|android13-5.10) SHORT=5.10 ;;
    android13-5.15|android14-5.15) SHORT=5.15 ;;
    android14-6.1) SHORT=6.1 ;;
    android15-6.6) SHORT=6.6 ;;
    android16-6.12) SHORT=6.12 ;;
    android17-6.18) SHORT=6.18 ;;
esac
if [ -z "$SHORT" ]; then
    SHORT=$(uname -r | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')
fi
KO="$MODDIR/lib/pid_guard/$SHORT/generic_pid_guard.ko"
if [ ! -f "$KO" ]; then
    echo "pid_guard: no ko for KMI $KMI_FULL ($SHORT)" >> "$LOG"
    write_status no_ko "$KMI_FULL" "$SHORT" 0
    exit 0
fi

HASH=$(conf_hash)
PREV=$(cat "$STATE/pid_guard.conf_hash" 2>/dev/null)
if loaded && [ -n "$HASH" ] && [ "$HASH" = "$PREV" ]; then
    hide_self
    write_status ok "$KMI_FULL" "$SHORT" 0
    exit 0
fi
if loaded; then
    # 参数改了就按新参数重载：否则 UID/comm 变更要等重启才生效
    if ! unload; then
        log "[!] pid_guard 参数已变更但卸载失败，暂时沿用旧参数"
        write_status stale "$KMI_FULL" "$SHORT" 1
        exit 1
    fi
fi

# Magisk / APatch 没有 ksud：不要把它们记成 insmod 失败（会在 load.log 里反复刷失败）
if [ ! -x "$KSUD" ]; then
    _alt=$(command -v ksud 2>/dev/null)
    if [ -n "$_alt" ]; then
        KSUD=$_alt
    else
        log "[=] pid_guard 跳过：当前管理器没有 ksud（Magisk/APatch 路径），状态记为 unsupported"
        write_status unsupported "$KMI_FULL" "$SHORT" 0
        exit 0
    fi
fi

"$KSUD" insmod "$KO" \
  target_uids="$UIDS" \
  target_comms="$COMMS" \
  exclude_comms="$EXCLUDES" >> "$LOG" 2>&1
rc=$?
if [ "$rc" -ne 0 ] || ! loaded; then
    log "[!] pid_guard insmod 失败 rc=$rc（SUSFS 规则不受影响）"
    rm -f "$STATE/pid_guard.conf_hash" 2>/dev/null
    write_status failed "$KMI_FULL" "$SHORT" "$rc"
    exit 1
fi
echo "$HASH" > "$STATE/pid_guard.conf_hash" 2>/dev/null
log "Loaded kernel module: $KO"
hide_self
write_status ok "$KMI_FULL" "$SHORT" 0
exit 0
