#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Optional PID guard bundled with the SUSFS manager.
# $1 is the KMI selected by load.sh (e.g. android15-6.6); do not guess.
# 幂等：enabled=1 且已加载时只补隐藏；enabled=0 时主动卸载（不必重启）。
# 本脚本的失败只写 state/pid_guard.status 与 load.log，不动 state/fail_count：
# 可选的 PID 隐藏失败不应该触发 SUSFS 自动加载暂停。
# 无路径调用（sh pid_guard.sh）时 ${0%/*} 会退化成脚本名，这里兜底到模块目录
case "$0" in
    */*) MODDIR=${0%/*} ;;
    *) MODDIR=/data/adb/modules/susfs_allinone ;;
esac
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
# 本脚本不 source common.sh（保持独立可测），时间戳逻辑与 common.sh 的 now_stamp 一致：
# 开机早期 RTC 未同步时 date 会给出 1970-xx-xx，日志里改用开机时长
now_stamp() {
    _ns_year=$(date +%Y 2>/dev/null)
    case "$_ns_year" in
        20[2-9][0-9]|2[1-9][0-9][0-9]|3[0-9][0-9][0-9]) date '+%F %T' 2>/dev/null ;;
        *)
            _ns_up=$(cut -d' ' -f1 /proc/uptime 2>/dev/null | cut -d. -f1)
            case "$_ns_up" in
                ''|*[!0-9]*) date '+%F %T' 2>/dev/null ;;
                *) printf '开机+%ss（RTC 未同步）' "$_ns_up" ;;
            esac
            ;;
    esac
}
loaded() { [ -d "$SYS_MOD/$MODNAME" ]; }
conf_hash() { cksum "$CONF" 2>/dev/null | awk '{print $1 "-" $2}'; }

# 规则命中多少个进程（只读 /proc，纯观测；用于让 status 有可核对的事实，
# 而不是只报 ok —— audit-legacy2 MAJ-5）
count_matched() {
    _cm_n=0
    [ -d /proc ] || { echo 0; return 0; }
    for _cm_p in /proc/[0-9]*; do
        _cm_pid=${_cm_p#/proc/}
        _cm_uid=""
        _cm_comm=""
        read -r _cm_uid < "$_cm_p/status" 2>/dev/null
        _cm_uid=${_cm_uid##*Uid:}
        _cm_uid=${_cm_uid%%[!0-9]*}
        [ -n "$_cm_uid" ] || continue
        _cm_comm=$(cat "$_cm_p/comm" 2>/dev/null)
        case ",$EXCLUDES," in
            *",$_cm_comm,"*) continue ;;
        esac
        # UID 命中
        _cm_hit=0
        _cm_r=$UIDS
        while [ -n "$_cm_r" ]; do
            case "$_cm_r" in
                *,*) _cm_t=${_cm_r%%,*}; _cm_r=${_cm_r#*,} ;;
                *) _cm_t=$_cm_r; _cm_r="" ;;
            esac
            case "$_cm_t" in
                *-*) _cm_lo=${_cm_t%%-*}; _cm_hi=${_cm_t##*-}
                     [ "$_cm_uid" -ge "$_cm_lo" ] 2>/dev/null && [ "$_cm_uid" -le "$_cm_hi" ] 2>/dev/null && _cm_hit=1 ;;
                '') ;;
                *) [ "$_cm_uid" = "$_cm_t" ] && _cm_hit=1 ;;
            esac
            [ "$_cm_hit" = "1" ] && break
        done
        # comm 前缀命中（只支持尾部 *）
        [ "$_cm_hit" = "0" ] && _cm_r=$COMMS
        while [ "$_cm_hit" = "0" ] && [ -n "$_cm_r" ]; do
            case "$_cm_r" in
                *,*) _cm_t=${_cm_r%%,*}; _cm_r=${_cm_r#*,} ;;
                *) _cm_t=$_cm_r; _cm_r="" ;;
            esac
            case "$_cm_t" in
                *'*') _cm_pre=${_cm_t%'*'}; case "$_cm_comm" in "$_cm_pre"*) _cm_hit=1 ;; esac ;;
                *) [ "$_cm_comm" = "$_cm_t" ] && _cm_hit=1 ;;
            esac
        done
        [ "$_cm_hit" = "1" ] && _cm_n=$((_cm_n + 1))
    done
    echo "$_cm_n"
}

write_status() {
    {
        echo "result=$1"
        echo "kmi=${2:-}"
        echo "short=${3:-}"
        echo "rc=${4:-0}"
        [ -n "${5:-}" ] && echo "matched=${5}"
        echo "ts=$(now_stamp)"
    } > "$STATE/pid_guard.status" 2>/dev/null
}

# /proc/modules 里可见时补一条隐藏，与 hide_modules.txt 同一条内核接口
hide_self() {
    [ -e "$HIDE_LIST" ] || return 0
    grep -qw -- "$MODNAME" "$HIDE_LIST" 2>/dev/null && return 0
    if echo "add $MODNAME" > "$HIDE_LIST" 2>/dev/null; then
        log "[+] hide_module $MODNAME"
    else
        log "[=] hide_module $MODNAME (失败)"
    fi
}

unhide_self() {
    [ -e "$HIDE_LIST" ] || return 0
    grep -qw -- "$MODNAME" "$HIDE_LIST" 2>/dev/null || return 0
    echo "del $MODNAME" > "$HIDE_LIST" 2>/dev/null && log "[-] hide_module $MODNAME 已移除"
}

unload() {
    # 无操作时不写日志：load.sh 与 apply.sh 都会调用本脚本，
    # 每次启动会打印两遍同一行，看着像重复卸载
    loaded || { write_status skipped "" "" 0; return 0; }
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

PG_BAD=""
pg_reject() { PG_BAD=$1; }

# 允许字符：字母数字与 _,.:/@+- ；comm 额外允许 * 但只能作后缀
pg_value_ok() {
    case "$1" in
        *[!A-Za-z0-9_,.:/@+*-]*) return 1 ;;
        *,|,*|*,,*|*" "*) return 1 ;;
    esac
    return 0
}

# UID 只接受数字或数字-数字（99000 / 99000-99999）
pg_uids_ok() {
    [ -n "$1" ] || return 0
    _pu=""
    _pr=$1
    while :; do
        case "$_pr" in
            *,*) _pt=${_pr%%,*}; _pr=${_pr#*,} ;;
            *) _pt=$_pr; _pr="" ;;
        esac
        case "$_pt" in
            ''|*[!0-9-]*|*-*-*|-*|*-) return 1 ;;
        esac
        [ -n "$_pr" ] || break
    done
    return 0
}

# comm 通配只允许尾部一个 *（与 pid_guard_ctl.sh 的写入口校验保持同一套，audit-legacy2 MAJ-4）
pg_comms_wildcard_ok() {
    [ -n "$1" ] || return 0
    _pw_r=$1
    while :; do
        case "$_pw_r" in
            *,*) _pw_t=${_pw_r%%,*}; _pw_r=${_pw_r#*,} ;;
            *) _pw_t=$_pw_r; _pw_r="" ;;
        esac
        case "$_pw_t" in
            *'*'*)
                _pw_rest=${_pw_t%'*'}
                case "$_pw_rest" in
                    ''|*'*'*) return 1 ;;
                esac
                ;;
        esac
        [ -n "$_pw_r" ] || break
    done
    return 0
}

[ -f "$CONF" ] || exit 0

ENABLED=$(conf_get enabled)
UIDS=$(conf_get target_uids)
COMMS=$(conf_get target_comms)
EXCLUDES=$(conf_get exclude_comms)
case "$ENABLED" in 1) ;; *) ENABLED=0 ;; esac

pg_value_ok "$UIDS"     || pg_reject "target_uids 含非法字符/空项/空格"
pg_uids_ok "$UIDS"      || pg_reject "target_uids 只能是数字或 数字-数字"
pg_value_ok "$COMMS"    || pg_reject "target_comms 含非法字符/空项/空格"
pg_value_ok "$EXCLUDES" || pg_reject "exclude_comms 含非法字符/空项/空格"
case "$UIDS$EXCLUDES" in *'*'*) pg_reject "UID/排除项不允许 *" ;; esac
case ",$COMMS," in
    *",*,"*|*",**,"*) pg_reject "目标 comm 的 * 只能作后缀，不能是裸 *" ;;
esac
pg_comms_wildcard_ok "$COMMS" || pg_reject "目标 comm 的 * 只能出现在末尾（前缀匹配）"
[ -n "$UIDS$COMMS" ] || pg_reject "target_uids 与 target_comms 不能同时为空"

if [ -n "$PG_BAD" ]; then
    log "[!] pid_guard 配置被拒绝：$PG_BAD（本次不加载，修好保存后自动重试）"
    write_status bad_conf "" "" 2
    # 即便配置无效，enabled=0 的意图仍然要执行（关掉就该卸载）
    if [ "$ENABLED" != "1" ]; then
        unload || true
    fi
    exit 0
fi

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
    write_status ok "$KMI_FULL" "$SHORT" 0 "$(count_matched)"
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
# 不用 ksud 的原话：ksud insmod 自己会输出「Loaded kernel module: <path>」，
# 再打一遍日志里就是两行一模一样的内容
log "[i] pid_guard 已加载（KMI $SHORT，参数已生效）"
hide_self
write_status ok "$KMI_FULL" "$SHORT" 0 "$(count_matched)"
exit 0
