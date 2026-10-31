#!/system/bin/sh
# 离线单元测试：sus_path 清理只作用于本模块写入的路径
set -u
REPO="$1"
TMP=$(mktemp -d); mkdir -p "$TMP/state"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1  expect=[$3] got=[$2]"; fail=1; fi; }

# 直接加载 common.sh（其中只有函数与默认变量赋值）
MODDIR="$TMP"; mkdir -p "$TMP/config" "$TMP/state"; SUSFS_PATH_NODE="$TMP/node"; : > "$SUSFS_PATH_NODE"
. "$REPO/common.sh"

# 场景 1：记录去重
record_our_path /data/adb/x; record_our_path /data/adb/x; record_our_path /data/data/y
chk "记录去重" "$(wc -l < "$STATE/our_paths.txt" | tr -d " ")" "2"

# 场景 2：只删自己清单里的路径
: > "$SUSFS_PATH_NODE"
clear_own_paths >/dev/null
chk "删除条数" "$(grep -c "^del " "$SUSFS_PATH_NODE")" "2"
chk "不含他人路径" "$(grep -c "del /data/data/other" "$SUSFS_PATH_NODE" || true)" "0"
chk "清单已清空" "$(wc -c < "$STATE/our_paths.txt" | tr -d " ")" "0"

# 场景 3：无清单时不发任何删除命令
: > "$SUSFS_PATH_NODE"
clear_own_paths >/dev/null
chk "无清单不发命令" "$(wc -l < "$SUSFS_PATH_NODE" | tr -d " ")" "0"

# 场景 3b：首次迁移按配置清理，且只清配置内的路径
: > "$SUSFS_PATH_NODE"
printf '/data/adb\n# 注释\non\n/data/data/app1\n' > "$TMP/cfg.txt"
clear_migrated_paths "$TMP/cfg.txt" >/dev/null
chk "迁移仅删合法路径" "$(grep -c "^del " "$SUSFS_PATH_NODE")" "2"
chk "迁移忽略非路径" "$(grep -c "^del on$" "$SUSFS_PATH_NODE" || true)" "0"

# 场景 3c：清单里若有别人的路径，删除范围只限清单内（清单本身决定范围）
: > "$SUSFS_PATH_NODE"
printf '/data/adb\n' > "$STATE/our_paths.txt"
: > "$SUSFS_PATH_NODE"
clear_own_paths >/dev/null
chk "只删清单内路径" "$(grep -c "^del " "$SUSFS_PATH_NODE")" "1"
chk "未波及清单外路径" "$(grep -c "del /data/data/other" "$SUSFS_PATH_NODE" || true)" "0"

# 场景 3d：删除失败时清单必须保留（不能变成孤儿规则）
rm -f "$SUSFS_PATH_NODE"
printf '/data/adb\n' > "$STATE/our_paths.txt"
clear_own_paths >/dev/null
chk "删除失败保留清单" "$(grep -c "^/data/adb$" "$STATE/our_paths.txt")" "1"

# 集成断言：apply 只在 add 成功后才登记清单
chk "成功后才记录" "$(grep -c 'record_our_path "$path"' "$REPO/apply.sh")" "1"
chk "不再预登记" "$(grep -B2 'record_our_path "$path"' "$REPO/apply.sh" | grep -c '记入本模块的期望清单')" "0"

# 场景 4：显式整表清空
: > "$SUSFS_PATH_NODE"
clear_all_paths
chk "整表清空用 clear" "$(cat "$SUSFS_PATH_NODE")" "clear"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"