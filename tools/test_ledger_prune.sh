#!/bin/sh
# 回归：账本里历史遗留的「App 安装目录」规则必须被主动撤销（关掉开关也要清）
# 现场：用户早已把 hide_gapps 关掉，但内核里仍留着 /product/priv-app/GmsCore，
# 检测器持续报「安装记录与 APK 不符」。
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi

TMP=$(mktemp -d)
MOD="$TMP/mod"
mkdir -p "$MOD/state" "$MOD/config"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

# 用假的内核节点，观察 del 是否被写入
NODE="$TMP/susfs_path"
cat > "$NODE" <<EOF
path=/data/adb [ours:1]
path=/product/priv-app/GmsCore [ours:1]
path=/data/local/tmp/hy [ours:1]
EOF
mkdir -p "$MOD/state"
printf '%s\n' "/data/adb" "/product/priv-app/GmsCore" "/data/local/tmp/hy" > "$MOD/state/our_paths.txt"

MODDIR="$MOD" SUSFS_PATH_NODE="$NODE" . "$REPO/common.sh" >/dev/null 2>&1
# 只测分类函数与账本语义（apply.sh 的 prune 需要完整环境，用结构断言代替）
chk "分类：安装目录" "$(is_app_install_dir /product/priv-app/GmsCore && echo app || echo other)" "app"
chk "分类：数据目录" "$(is_app_install_dir /data/adb && echo app || echo other)" "other"

S="$REPO/apply.sh"
chk "apply.sh 有历史遗留清理" "$(grep -c '_prune_ledger_dirs()' "$S")" "1"
chk "清理在 sus_path 段之前执行" "$([ "$(grep -n '_prune_ledger_dirs$' "$S" | head -1 | cut -d: -f1)" -lt "$(grep -n '^# 5. sus_path' "$S" | cut -d: -f1)" ] && echo yes || echo no)" "yes"
chk "清理只删安装目录" "$(grep -c 'is_app_install_dir "$_pl_p" && susfs_path_del' "$S")" "1"
chk "删除失败时保留条目" "$(grep -c '_pl_tmp' "$S" | awk '{print ($1>=3)?"yes":"no"}')" "yes"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
