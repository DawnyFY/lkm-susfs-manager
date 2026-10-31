#!/bin/sh
# 离线测试：KMI 必须用真实内核选择（抽取 common.sh 的真实函数，不复制实现）
set -u
REPO="$1"
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

MODDIR="$TMP"; mkdir -p "$TMP/config" "$TMP/state"
. "$REPO/common.sh"
. "$REPO/kmi.sh"

# /proc/version 优先于 real_uname 快照（函数真实行为）
printf "Linux version 5.10.101-android12-9-gabc (builder@x) #1 SMP\n" > "$TMP/pv"
printf "release=6.12.35-android16-5-real\nversion=#1\n" > "$STATE/real_uname.txt"
chk "/proc/version 优先级" "$(PROC_VERSION_FILE="$TMP/pv" real_kernel_release)" "5.10.101-android12-9-gabc"

# /proc/version 无 android 标签时回退到快照
printf "Linux version 5.10.101 (builder@x) #1 SMP\n" > "$TMP/pv2"
chk "无 android 标签回退快照" "$(PROC_VERSION_FILE="$TMP/pv2" real_kernel_release)" "6.12.35-android16-5-real"

# 两者都不可用时回退 osrelease（本机有则比对，无则跳过）
if [ -r /proc/sys/kernel/osrelease ]; then
    chk "回退 osrelease" "$(PROC_VERSION_FILE=/nonexistent/pv real_kernel_release)" "$(cat /proc/sys/kernel/osrelease)"
else
    echo "SKIP  回退 osrelease（本机无 /proc/sys/kernel/osrelease）"
fi

# 真实内核与伪装值的匹配结果必须不同
chk "真实内核匹配" "$(select_kmi 6.12.35-android16-5-o-gb42c1af35b26-4k "$REPO")" "android16-6.12"
chk "伪装值会选错" "$(select_kmi 6.6.77-android15-8-gca30f3b4bef6-abogki440974771-4k "$REPO")" "android15-6.6"

# 集成断言：load.sh 必须通过 real_kernel_release 取版本，而不是直接读 osrelease
chk "load.sh 使用真实内核函数" "$(grep -c 'REL=$(real_kernel_release' "$REPO/load.sh")" "1"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"