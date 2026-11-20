#!/bin/sh
# 端到端测试：set_bundle 一次写入 7 个规则文件；非法内容整体不落盘
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi
TMP=$(mktemp -d)
MOD="$TMP/mod"; mkdir -p "$MOD/config" "$MOD/state"
sed "s#/data/adb/modules/susfs_allinone#$MOD#g" "$REPO/ctl.sh" > "$MOD/ctl.sh"
sed "s#/data/adb/modules/susfs_allinone#$MOD#g" "$REPO/common.sh" > "$MOD/common.sh"
cp "$REPO/kmi.sh" "$MOD/kmi.sh" 2>/dev/null || true
printf "id=susfs_allinone\nversion=1.2.0\nversionCode=12\n" > "$MOD/module.prop"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

b64() { printf "%s" "$1" | base64 | tr -d "\n"; }

# 构造 bundle：config|sus_path|hide_modules|skip_hide|sus_mount|try_umount
seg2() {
    # v2 段格式：<解码后字节数>:<base64>
    printf "%s:%s" "$(printf "%s" "$1" | wc -c | tr -d " ")" "$(b64 "$1")"
}

# v1（1.2.8 及更早）：每段只有 base64，用于验证向后兼容
make_bundle_v1() {
    printf "%s|%s|%s|%s|%s|%s|%s|%s" \
        "$(b64 "$1")" "$(b64 "$2")" "$(b64 "$3")" "$(b64 "$4")" "$(b64 "$5")" "$(b64 "$6")" "$(b64 "${7:-}")" "$(b64 "${8:-}")" | base64 | tr -d "\n"
}

make_bundle() {
    # 8 段：config|sus_path|sus_path_loop|hide_modules|skip_hide|sus_mount|try_umount|sus_map
    printf "%s|%s|%s|%s|%s|%s|%s|%s" \
        "$(seg2 "$1")" "$(seg2 "$2")" "$(seg2 "$3")" "$(seg2 "$4")" "$(seg2 "$5")" "$(seg2 "$6")" "$(seg2 "${7:-}")" "$(seg2 "${8:-}")" | base64 | tr -d "\n"
}

run_bundle() {
    MODDIR="$MOD" sh "$MOD/ctl.sh" set_bundle "$1" 2>&1 | tail -1
}

cfg=$(printf "# 配置\nauto_load=1\nreplace_rules=1\n")
ok=$(make_bundle "$cfg" "/data/adb" "/data/adb/loop_dir" "kernelsu" "duckdetector" "# mount" "# umount" "/data/adb/modules/x/lib.so")
chk "bundle 写入成功" "$(run_bundle "$ok")" "saved"
chk "config 落盘" "$(grep -c "^auto_load=1$" "$MOD/config/config.ini")" "1"
chk "sus_path 落盘" "$(cat "$MOD/config/sus_path.txt")" "/data/adb"
chk "sus_path_loop 落盘" "$(cat "$MOD/config/sus_path_loop.txt")" "/data/adb/loop_dir"
chk "hide_modules 落盘" "$(cat "$MOD/config/hide_modules.txt")" "kernelsu"
chk "skip_hide 落盘" "$(cat "$MOD/config/skip_hide.txt")" "duckdetector"
chk "sus_mount 落盘" "$(cat "$MOD/config/sus_mount.txt")" "# mount"
chk "try_umount 落盘" "$(cat "$MOD/config/try_umount.txt")" "# umount"
chk "sus_map 落盘" "$(cat "$MOD/config/sus_map.txt")" "/data/adb/modules/x/lib.so"

# 非法 config：整体拒绝，已有文件不被破坏
bad_cfg=$(printf "auto_load=1 MODDIR=/tmp/evil\n")
bad=$(make_bundle "$bad_cfg" "/x" "/loop" "y" "z" "a" "b")
chk "非法 config 被拒" "$(run_bundle "$bad")" "rejected: config: line 1: whitespace in value"
chk "拒绝后 config 未被破坏" "$(grep -c "^auto_load=1$" "$MOD/config/config.ini")" "1"
chk "拒绝后 sus_path 未被破坏" "$(cat "$MOD/config/sus_path.txt")" "/data/adb"

# 段数不足：仍按顺序解析，但不应写入垃圾
short=$(printf "%s|%s" "$(b64 "auto_load=1")" "$(b64 "/p")" | base64 | tr -d "\n")
chk "段数不足被拒绝" "$(run_bundle "$short")" "rejected: expect 8 segments, got 2"

# 非 base64
chk "非法 base64 被拒" "$(run_bundle "!!!notbase64!!!")" "invalid base64"

# 回归（1.2.8 曾出现）：单层编码 —— 原文直接 join 后整体 base64。
# ctl.sh 用 cut -d'|' 逐行取段，多行原文会被切碎，toybox 的 base64 -d 对垃圾输入仍返回 0，
# 结果 8 个文件全被写成 0 字节却回 "saved"。这里断言它必须被拒绝且不破坏现有文件。
raw_bad=$(printf "# 注释
auto_load=1
hide_sus_mnts=1
|/data/adb
|/loop
|kernelsu
|skip
|mount
|umount
|map
")
single=$(printf "%s" "$raw_bad" | base64 | tr -d "
")
out=$(run_bundle "$single")

# 平台差异：GNU 的 base64 -d 对垃圾输入返回非 0，toybox 返回 0。
# - GNU 下由 base64 自己拒绝，测不出新防线 → 只断言"被拒绝且文件完好"（回归价值仍在）
# - toybox 下必须命中 1.2.8 新增的防线文案，否则等于空转
if printf 'not-base64!!' | base64 -d >/dev/null 2>&1; then
    BASE64_LENIENT=1
else
    BASE64_LENIENT=0
fi

case "$out" in
    rejected*)
        if [ "$BASE64_LENIENT" = "1" ]; then
            case "$out" in
                *"(空输出)"*|*"config.ini 为空"*|*"内容不完整"*)
                    echo "PASS  单层编码被新防线拒绝（toybox 语义：$out）" ;;
                *) echo "FAIL  toybox 语义下未命中新防线 got=[$out]"; fail=1 ;;
            esac
        else
            echo "PASS  单层编码被拒绝（GNU base64 自身拒绝：$out）"
        fi ;;
    *) echo "FAIL  单层编码未被拒绝 got=[$out]"; fail=1 ;;
esac
chk "单层编码后 config 未被清空" "$(grep -c "^auto_load=1$" "$MOD/config/config.ini")" "1"
chk "单层编码后 sus_path 未被清空" "$(cat "$MOD/config/sus_path.txt")" "/data/adb"

# v2 长度校验：声明长度与实际不符（模拟 base64 4 字符边界截断）
# 把 sus_path 段的 base64 截短到 4 的倍数、长度前缀保持原值 —— 全长仍是合法 base64
inner=$(printf '%s' "$ok" | base64 -d)
seg=$(printf '%s' "$inner" | cut -d'|' -f2)
head=${seg%%:*}
body=${seg#*:}
short=$(printf '%s' "$body" | cut -c1-8)
tampered=$(printf '%s' "$inner" | awk -v s="$head:$short" -F'|' 'BEGIN{OFS="|"}{$2=s; print}')
tampered_payload=$(printf "%s" "$tampered" | base64 | tr -d "\n")
out2=$(run_bundle "$tampered_payload")
case "$out2" in
    *"长度不符"*) echo "PASS  长度不符被拒绝（$out2）" ;;
    *) echo "FAIL  长度不符未被拒绝 got=[$out2]"; fail=1 ;;
esac
chk "长度不符后 config 未被破坏" "$(grep -c "^auto_load=1$" "$MOD/config/config.ini")" "1"

# 向后兼容：v1 格式（无长度前缀）仍应写入成功
v1=$(make_bundle_v1 "$cfg" "/data/v1" "/loop" "kernelsu" "duck" "# m" "# u")
chk "v1 格式仍兼容" "$(run_bundle "$v1")" "saved"
chk "v1 内容正确" "$(cat "$MOD/config/sus_path.txt")" "/data/v1"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"