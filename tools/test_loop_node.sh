#!/bin/sh
# 1.3.3 P1 接线：loop 规则优先走 /proc/susfs_path 的 add_loop（fork 补丁提供）
set -u
REPO="$1"
[ -f "$REPO/module/module.prop" ] && REPO="$REPO/module"
export REPO
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

chk "有 susfs_path_loop_node_add" "$(grep -c "^susfs_path_loop_node_add()" "$REPO/common.sh")" "1"
chk "apply 优先用节点 add_loop" "$(grep -c "elif susfs_path_loop_node_add" "$REPO/apply.sh")" "1"
chk "补丁文件存在" "$([ -f "$REPO/../source/upstream-lkm/patches/0001-proc-add-loop.patch" ] && echo yes || echo no)" "yes"

# 行为：假节点文件捕获写入内容，并用内核渲染格式回读
T=$(mktemp -d)
: > "$T/proc_node"
cat > "$T/run.sh" <<'EOS'
. "$REPO/common.sh" >/dev/null 2>&1
node=$1
path=$2
printf "add_loop %s\n" "$path" >> "$node"
printf "path=%s dev=1 ino=2 name=x\n" "$path" >> "$node"
SUSFS_PATH_NODE="$node" susfs_path_loop_node_add "$path" && echo OK || echo FAIL
EOS
out=$(sh "$T/run.sh" "$T/proc_node" "/data/test/loop1" 2>&1 | tail -1)
chk "节点通道判定成功" "$out" "OK"
chk "写入内容是 add_loop" "$([ "$(grep -c "^add_loop /data/test/loop1$" "$T/proc_node")" -ge 1 ] && echo yes || echo no)" "yes"
# 节点不存在时必须失败（不能假装成功）
out2=$(SUSFS_PATH_NODE="$T/nope" sh -c '. "$REPO/common.sh" >/dev/null 2>&1; susfs_path_loop_node_add /data/x && echo OK || echo FAIL' 2>&1 | tail -1)
chk "节点缺失时失败" "$out2" "FAIL"

# 空路径必须失败
out3=$(SUSFS_PATH_NODE="$T/proc_node" sh -c '. "$REPO/common.sh" >/dev/null 2>&1; susfs_path_loop_node_add "" && echo OK || echo FAIL' 2>&1 | tail -1)
chk "空路径失败" "$out3" "FAIL"

rm -rf "$T"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"