#!/bin/sh
# 反变异：doctor 必须能报出配置问题（干净配置不许误报）；节点写入失败必须判失败
set -u
REPO="$1"
[ -f "$REPO/module/module.prop" ] && REPO="$REPO/module"
export REPO
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

T=$(mktemp -d)
mkdir -p "$T/config" /tmp/aimod_exists
printf "/data/nope-a\nrelative/path\n/data/nope-a\n" > "$T/config/sus_path.txt"
printf "/tmp/aimod_exists\n" > "$T/config/sus_path_loop.txt"
printf "kernelsu\n" > "$T/config/hide_modules.txt"
printf "enabled=1\ntarget_uids=\ntarget_comms=\n" > "$T/config/pid_guard.conf"
printf "no-slash-prefix\n" > "$T/config/sus_mount.txt"
printf '. "$REPO/common.sh" >/dev/null 2>&1\ndoctor_scan "$1"\n' > "$T/run.sh"
out=$(sh "$T/run.sh" "$T/config" 2>&1)
chk "doctor 报出问题数" "$(printf "%s" "$out" | grep -c "处需要注意")" "1"
chk "doctor 命中非绝对路径" "$(printf "%s" "$out" | grep -c "非绝对路径")" "1"
chk "doctor 命中不存在路径" "$(printf "%s" "$out" | grep -c "路径不存在")" "1"
chk "doctor 命中重复条目" "$(printf "%s" "$out" | grep -c "重复条目")" "1"
chk "doctor 命中挂载前缀" "$(printf "%s" "$out" | grep -c "未以 / 开头")" "1"
chk "doctor 命中 pid_guard 空规则" "$(printf "%s" "$out" | grep -c "UID 与进程名都为空")" "1"

C=$(mktemp -d); mkdir -p "$C/config"
printf "/tmp/aimod_exists\n" > "$C/config/sus_path.txt"
printf "enabled=0\n" > "$C/config/pid_guard.conf"
out2=$(sh "$T/run.sh" "$C/config" 2>&1)
chk "干净配置不误报" "$(printf "%s" "$out2" | grep -c "未发现明显问题")" "1"

D=$(mktemp -d); mkdir -p "$D/nodedir"
printf '. "$REPO/common.sh" >/dev/null 2>&1\nBIN=""\nsusfs_path_add /tmp/aimod_exists && echo OK || echo FAIL\n' > "$T/add.sh"
rc=$(SUSFS_PATH_NODE="$D/nodedir" sh "$T/add.sh" 2>&1 | tail -1)
chk "节点不可写必须判失败" "$rc" "FAIL"

# 变异 V1：节点写入「成功但读不回」（/dev/null）时，susfs_path_add 必须判失败
cat > "$T/add2.sh" <<EOS
. "$REPO/common.sh" >/dev/null 2>&1
BIN=""
susfs_path_add /tmp/aimod_exists && echo OK || echo FAIL
EOS
rc2=$(SUSFS_PATH_NODE=/dev/null sh "$T/add2.sh" 2>&1 | tail -1)
chk "写成功但读不回必须判失败" "$rc2" "FAIL"

rm -rf "$T" "$C" "$D" /tmp/aimod_exists
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"