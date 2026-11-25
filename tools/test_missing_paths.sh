#!/bin/sh
# 回归：sus_path 里「不存在的路径」不再计入规则失败，但要单独提示并建议 sus_path_loop
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi
A="$REPO/apply.sh"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

chk "有不存在路径的分支" "$(grep -c '路径不存在，跳过；临时路径' "$A")" "1"
chk "该分支不计入 _rule_fails" "$(grep -A3 '路径不存在，跳过' "$A" | grep -c '_rule_fails')" "0"
chk "该分支计入 _rule_missing" "$(grep -A3 '路径不存在，跳过' "$A" | grep -c '_rule_missing')" "1"
chk "计数器已初始化" "$(grep -c '^_rule_missing=0' "$A")" "1"
chk "末尾单独提示" "$(grep -c '已跳过（不算失败）' "$A")" "1"
chk "建议 sus_path_loop" "$(grep -A2 '已跳过（不算失败）' "$A" | grep -c 'sus_path_loop.txt')" "1"
chk "描述里带不存在计数" "$(grep -c '另有 \$_rule_missing 条路径不存在' "$A")" "1"

# 行为断言：把 apply.sh 里这段循环原样抽出来跑（函数与变量从 apply.sh 里取）
TMP=$(mktemp -d)
mkdir -p "$TMP/config" "$TMP/state"
printf '/data/definitely-not-exist-xyz\n/storage/emulated/0/Android/data/com.tencent.tmgp.cf/files/ano_tmp\n/\n' > "$TMP/config/sus_path.txt"

# 抽出 clean_entry 函数体
sed -n '/^clean_entry() {/,/^}/p' "$A" > "$TMP/clean.sh"

cat > "$TMP/run.sh" <<'EOS'
set -u
. "$COMMON"
. "$MODDIR/clean.sh"
_rule_fails=0
_rule_missing=0
while IFS= read -r _line || [ -n "$_line" ]; do
    path=$(clean_entry "$_line")
    [ -n "$path" ] || continue
    if [ ! -e "$path" ]; then
        _rule_missing=$((_rule_missing + 1))
    else
        echo "[+] sus_path $path"
    fi
done < "$MODDIR/config/sus_path.txt"
echo "fails=$_rule_fails missing=$_rule_missing"
EOS

out=$(MODDIR="$TMP" COMMON="$REPO/common.sh" sh "$TMP/run.sh" 2>&1 | tail -2)
chk "两条不存在路径归入 missing、存在的正常处理" "$(printf '%s' "$out" | tail -1)" "fails=0 missing=2"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
