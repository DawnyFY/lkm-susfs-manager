#!/bin/sh
# 离线回归：虚拟/临时路径判定（is_ephemeral_path）
# 线上日志里 /sys/fs/cgroup/apps/uid_10386 每次都失败，把 apply 从 success 降成 partial。
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi

TMP=$(mktemp -d)
MOD="$TMP/mod"
mkdir -p "$MOD/state" "$MOD/config"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

# 只取 is_ephemeral_path 的实现，不跑 common.sh 的其余初始化
. "$REPO/common.sh" >/dev/null 2>&1

ephemeral() { if is_ephemeral_path "$1"; then echo yes; else echo no; fi; }

chk "/sys/fs/cgroup 本身"        "$(ephemeral /sys/fs/cgroup)"              "yes"
chk "/sys/fs/cgroup/apps/uid_10386" "$(ephemeral /sys/fs/cgroup/apps/uid_10386)" "yes"
chk "/dev/cpuset/AppOpt"          "$(ephemeral /dev/cpuset/AppOpt)"          "yes"
chk "/dev/memcg/apps"             "$(ephemeral /dev/memcg/apps)"             "yes"
chk "/dev/blkio"                  "$(ephemeral /dev/blkio)"                  "yes"
chk "/sys/fs/bpf/x"               "$(ephemeral /sys/fs/bpf/x)"               "yes"
chk "/proc/self/maps"             "$(ephemeral /proc/self/maps)"             "yes"

# 正常可隐藏的路径不能被误判
chk "/data/adb"                   "$(ephemeral /data/adb)"                   "no"
chk "/data/local/tmp/brevent"     "$(ephemeral /data/local/tmp/brevent)"     "no"
chk "/system/priv-app/GmsCore"    "$(ephemeral /system/priv-app/GmsCore)"    "no"
chk "/sdcard/Android/data"        "$(ephemeral /sdcard/Android/data)"        "no"
chk "/data/system"                "$(ephemeral /data/system)"                "no"
chk "/sys/kernel/debug"           "$(ephemeral /sys/kernel/debug)"           "no"
chk "/systemfs/data"              "$(ephemeral /systemfs/data)"              "no"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
