#!/bin/sh
# 回归：audit-legacy2 的 MAJOR 修复
#  MAJ-1 load.sh errno 精确比较（EEXIST 不能被当成 EPERM）
#  MAJ-2 spoof_uname_version 的值能穿过校验与注释剥离
#  MAJ-4 pid_guard.sh 读取侧也拒绝非后缀 *
#  MAJ-6 「恢复默认」保留 anonymous_stats
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

T=$(mktemp -d)
mkdir -p "$T/config" "$T/state"
sed "s#/data/adb/modules/susfs_allinone#$T#g" "$REPO/ctl.sh" > "$T/ctl.sh"
sed "s#/data/adb/modules/susfs_allinone#$T#g" "$REPO/common.sh" > "$T/common.sh"
sed "s#/data/adb/modules/susfs_allinone#$T#g" "$REPO/pid_guard.sh" > "$T/pid_guard.sh"
printf 'id=susfs_allinone\nversion=1.3.0\nversionCode=22\n' > "$T/module.prop"

# MAJ-1：源码层面确认不再用子串匹配 errno 1，并有精确解析
L="$REPO/load.sh"
chk "MAJ-1 不再子串匹配 errno 1" "$(grep -c '\*\"errno 1\"\*' "$L")" "0"
chk "MAJ-1 有精确 errno 解析" "$(grep -c '_ins_errno=' "$L")" "2"
chk "MAJ-1 用 1: 前缀判定 EPERM" "$(grep -c '1:\*|' "$L")" "1"

# MAJ-2：校验接受、注释剥离不吞
printf 'auto_load=1\nspoof_uname_version=#1 SMP PREEMPT\n' > "$T/c.ini"
B=$(base64 < "$T/c.ini" | tr -d '\n')
chk "MAJ-2 set_config 接受含 # 与空格的版本串" "$(sh "$T/ctl.sh" set_config "$B" 2>&1 | tail -1)" "saved"
chk "MAJ-2 落盘值完整" "$(grep '^spoof_uname_version=' "$T/config/config.ini")" "spoof_uname_version=#1 SMP PREEMPT"
printf 'manager_name=ab#cd\n' > "$T/c2.ini"
B2=$(base64 < "$T/c2.ini" | tr -d '\n')
chk "MAJ-2 其它键带 # 仍拒绝" "$(sh "$T/ctl.sh" set_config "$B2" 2>&1 | tail -1 | cut -c1-8)" "rejected"
chk "MAJ-2 apply 会回读 uname -r 核对" "$(grep -c '_un_r=$(uname -r' "$REPO/apply.sh")" "1"

# MAJ-4：读取侧拒绝中间通配
pg_try() {
    printf 'enabled=1\ntarget_uids=\ntarget_comms=%s\nexclude_comms=\n' "$1" > "$T/config/pid_guard.conf"
    PG_SYS_MOD="$T/nosys" PG_PROC_MODULES="$T/nomod" PG_HIDE_LIST="$T/nohide" PG_KSUD="$T/noksud" \
        sh "$T/pid_guard.sh" android15-6.6 >/dev/null 2>&1
    grep -q '^result=bad_conf' "$T/state/pid_guard.status" 2>/dev/null && echo REJECT || echo OK
}
chk "MAJ-4 读取侧拒绝 *a*" "$(pg_try '*a*')" "REJECT"
chk "MAJ-4 读取侧拒绝 *sh" "$(pg_try '*sh')" "REJECT"
chk "MAJ-4 读取侧放行 sh*" "$(pg_try 'probe-*')" "OK"

# MAJ-6：reset 保留隐私开关
printf 'auto_load=1\nanonymous_stats=0\navc_spoof=1\n' > "$T/config/config.ini"
sh "$T/ctl.sh" reset_defaults >/dev/null 2>&1
chk "MAJ-6 reset 后仍为 0" "$(grep '^anonymous_stats=' "$T/config/config.ini")" "anonymous_stats=0"
chk "MAJ-6 reset 有备份" "$(ls -d "$T"/config.bak.* 2>/dev/null | wc -l | tr -d ' ')" "1"

rm -rf "$T"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
