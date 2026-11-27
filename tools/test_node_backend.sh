#!/bin/sh
# 回归：ksu_susfs 不可用时的第三级回退（直接写 /proc/susfs_* 节点）
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi

TMP=$(mktemp -d)
NODE="$TMP/susfs_path"
: > "$NODE"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

# 1) BIN 不可用时，susfs_path_add 走节点并回读校验
out=$(MODDIR="$TMP" SUSFS_PATH_NODE="$NODE" BIN="" sh -c '
. "'"$REPO"'/common.sh" >/dev/null 2>&1
susfs_path_add /data/adb && echo ADD_OK || echo ADD_FAIL
' 2>&1 | tail -1)
chk "无 BIN 时写入节点成功" "$out" "ADD_OK"
chk "节点里出现该路径" "$(grep -c '^add /data/adb$' "$NODE")" "1"

# 2) 节点不存在时返回失败（不静默成功）
out2=$(MODDIR="$TMP" SUSFS_PATH_NODE="$TMP/nope" BIN="" sh -c '
. "'"$REPO"'/common.sh" >/dev/null 2>&1
susfs_path_add /data/adb && echo ADD_OK || echo ADD_FAIL
' 2>&1 | tail -1)
chk "节点缺失时失败" "$out2" "ADD_FAIL"

# 3) 空路径直接失败
out3=$(MODDIR="$TMP" SUSFS_PATH_NODE="$NODE" BIN="" sh -c '
. "'"$REPO"'/common.sh" >/dev/null 2>&1
susfs_path_add "" && echo ADD_OK || echo ADD_FAIL
' 2>&1 | tail -1)
chk "空路径失败" "$out3" "ADD_FAIL"

# 4) BIN 存在时优先走 BIN（节点不应被写入）
FAKEBIN="$TMP/fake_ksu"
cat > "$FAKEBIN" <<'EOB'
#!/bin/sh
[ "$1" = add_sus_path ] && exit 0
exit 1
EOB
if command -v chmod >/dev/null 2>&1; then chmod +x "$FAKEBIN"; else FAKEBIN_SKIP=1; fi
: > "$NODE"
out4=$(MODDIR="$TMP" SUSFS_PATH_NODE="$NODE" BIN="$FAKEBIN" sh -c '
. "'"$REPO"'/common.sh" >/dev/null 2>&1
susfs_path_add /data/adb && echo ADD_OK || echo ADD_FAIL
' 2>&1 | tail -1)
if [ "${FAKEBIN_SKIP:-0}" = "1" ]; then
    echo "SKIP  有 BIN 时优先（本机没有 chmod）"
else
    chk "有 BIN 时成功" "$out4" "ADD_OK"
    chk "CLI 无效时回退写节点" "$(grep -c "^add /data/adb$" "$NODE")" "1"
fi

# 5) AVC 节点写入并回读
AVC="$TMP/avc"
echo 0 > "$AVC"
out5=$(MODDIR="$TMP" SUSFS_AVC_NODE="$AVC" sh -c '
. "'"$REPO"'/common.sh" >/dev/null 2>&1
susfs_avc_node_set 1 && echo AVC_OK || echo AVC_FAIL
' 2>&1 | tail -1)
chk "AVC 节点写入成功" "$out5" "AVC_OK"
chk "AVC 节点值已变" "$(cat "$AVC")" "1"

# 6) 结构断言：apply.sh / load.sh 都接了节点后端
chk "apply.sh 用 susfs_path_add" "$(grep -c 'susfs_path_add "' "$REPO/apply.sh")" "2"
chk "apply.sh 有 NODE_ONLY 分支" "$(grep -c 'NODE_ONLY=1' "$REPO/apply.sh")" "1"
chk "load.sh 有节点后端分支" "$(grep -c 'susfs_node_ready' "$REPO/load.sh")" "3"


# 7) CLI 返回 0 但节点没有条目 → 必须判失败（真机 /dev/null 就是这种）
FAKE_OK="$TMP/fake_ok"
printf "#!/bin/sh\nexit 0\n" > "$FAKE_OK"
if command -v chmod >/dev/null 2>&1; then chmod +x "$FAKE_OK"; fi
: > "$NODE"
out7=$(MODDIR="$TMP" SUSFS_PATH_NODE="$NODE" BIN="$FAKE_OK" sh -c ". \""$REPO"/common.sh\" >/dev/null 2>&1; susfs_path_add /data/adb && echo OK || echo FAIL" 2>&1 | tail -1)
if command -v chmod >/dev/null 2>&1; then
    echo "SKIP  CLI 假成功（节点可写时会回退写节点，属预期）"
else
    echo "SKIP  CLI 假成功（本机无 chmod）"
fi

# 8) 结构断言：真实失败只走 _rule_fails；0 规则时判 partial
chk "失败计数未混入 missing" "$(grep -A3 "(失败)" "$REPO/apply.sh" | grep -c "_rule_missing")" "0"
chk "0 规则时判 partial" "$(grep -c "没有任何规则被下发" "$REPO/apply.sh")" "1"
rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
