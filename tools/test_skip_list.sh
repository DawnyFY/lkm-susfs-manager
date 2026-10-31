#!/bin/sh
# 离线测试：跳过隐藏列表来自配置文件，而不是写死的包名
set -u
REPO="$1"
TMP=$(mktemp -d); mkdir -p "$TMP/config"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1  expect=[$3] got=[$2]"; fail=1; fi; }
MODDIR="$TMP"; mkdir -p "$TMP/config" "$TMP/state"
. "$REPO/common.sh"
verdict() { if is_detection_app_path "$1"; then echo skip; else echo hide; fi; }

# 默认列表
printf "# 注释\nduckdetector\nappvisibility\n" > "$CONFIG/skip_hide.txt"
chk "命中 duckdetector" "$(verdict /data/data/com.eltavine.duckdetector)" "skip"
chk "命中 appvisibility" "$(verdict /data/data/com.chunqiu.appvisibilitydemo)" "skip"
chk "普通应用不跳过" "$(verdict /data/data/com.tencent.mm)" "hide"
chk "注释行不生效" "$(verdict /data/data/foo#bar)" "hide"

# 用户自定义：加入 com.example.check
printf "com.example.check\n" > "$CONFIG/skip_hide.txt"
chk "自定义条目生效" "$(verdict /data/data/com.example.check)" "skip"
chk "未列出的检测器不再跳过" "$(verdict /data/data/com.eltavine.duckdetector)" "hide"

# 空文件 = 不跳过任何东西
: > "$CONFIG/skip_hide.txt"
chk "空列表不跳过" "$(verdict /data/data/com.eltavine.duckdetector)" "hide"

# 文件缺失 = 不跳过
rm -f "$CONFIG/skip_hide.txt"
chk "文件缺失不跳过" "$(verdict /data/data/com.eltavine.duckdetector)" "hide"

rm -rf "$TMP"

# 集成断言：apply.sh 必须调用 ensure_skip_hide_file；匹配逻辑必须读配置文件
chk "apply 生成默认列表" "$(grep -c '^ensure_skip_hide_file$' "$REPO/apply.sh")" "1"
chk "匹配读取配置文件" "$(grep -q 'skip_hide.txt' "$REPO/common.sh" && echo yes || echo no)" "yes"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"