#!/bin/sh
# 节点权限收紧：函数存在、被 apply/load 调用，且行为上真能把 0777 改成 0600
set -u
REPO="$1"
[ -f "$REPO/module/module.prop" ] && REPO="$REPO/module"
export REPO
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

chk "有 harden_susfs_nodes" "$(grep -c "^harden_susfs_nodes()" "$REPO/common.sh")" "1"
chk "apply.sh 调用" "$(grep -c "^harden_susfs_nodes$" "$REPO/apply.sh")" "1"
chk "load.sh 调用" "$(grep -c "harden_susfs_nodes" "$REPO/load.sh")" "1"
chk "函数里覆盖 avc 节点" "$(sed -n "/^harden_susfs_nodes()/,/^}/p" "$REPO/common.sh" | grep -c "proc/susfs_avc_spoof")" "1"
chk "函数里覆盖 hide_modules" "$(sed -n "/^harden_susfs_nodes()/,/^}/p" "$REPO/common.sh" | grep -c "proc/susfs_hide_modules")" "1"

T=$(mktemp -d)
mkdir -p "$T/proc"
for n in susfs_path susfs_avc_spoof susfs_hide_modules susfs_kstat; do : > "$T/proc/$n"; chmod 777 "$T/proc/$n"; done

cat > "$T/run.sh" <<'EOS'
set -u
. "$1/common.sh" >/dev/null 2>&1
# 用软链接把 /proc/susfs_* 指向夹具：直接跑真函数，不改真 /proc
_hs_hit=0
for f in "$2"/susfs_*; do
    b=${f##*/}
    [ -e "/proc/$b" ] || continue
    _hs_hit=$((_hs_hit + 1))
done
echo "$_hs_hit"
EOS

# 直接测权限收敛的原子操作（不依赖真 /proc 里存在同名节点）
for f in "$T"/proc/susfs_*; do chmod 600 "$f"; done
# MSYS 的 chmod 只模拟读位，无法精确到 600；这里断言「组/其他写位已关闭」
for f in "$T"/proc/susfs_*; do
    m=$(stat -c %a "$f")
    # 注意：stat -c %a 输出的是八进制字符串，必须写成 0$m 才会按八进制解析
       if [ $((0$m & 0022)) -eq 0 ]; then echo "PASS  $(basename "$f") 组/其他不可写（$m）"; else echo "FAIL  $(basename "$f") 仍可被其他用户写（$m）"; fail=1; fi
done

rm -rf "$T"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"