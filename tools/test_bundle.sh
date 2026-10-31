#!/bin/sh
# 端到端测试：set_bundle 一次写入 6 个文件；非法内容整体不落盘
set -u
REPO="$1"
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
make_bundle() {
    printf "%s|%s|%s|%s|%s|%s" \
        "$(b64 "$1")" "$(b64 "$2")" "$(b64 "$3")" "$(b64 "$4")" "$(b64 "$5")" "$(b64 "$6")" | base64 | tr -d "\n"
}

run_bundle() {
    MODDIR="$MOD" sh "$MOD/ctl.sh" set_bundle "$1" 2>&1 | tail -1
}

cfg=$(printf "# 配置\nauto_load=1\nreplace_rules=1\n")
ok=$(make_bundle "$cfg" "/data/adb" "kernelsu" "duckdetector" "# mount" "# umount")
chk "bundle 写入成功" "$(run_bundle "$ok")" "saved"
chk "config 落盘" "$(grep -c "^auto_load=1$" "$MOD/config/config.ini")" "1"
chk "sus_path 落盘" "$(cat "$MOD/config/sus_path.txt")" "/data/adb"
chk "hide_modules 落盘" "$(cat "$MOD/config/hide_modules.txt")" "kernelsu"
chk "skip_hide 落盘" "$(cat "$MOD/config/skip_hide.txt")" "duckdetector"
chk "sus_mount 落盘" "$(cat "$MOD/config/sus_mount.txt")" "# mount"
chk "try_umount 落盘" "$(cat "$MOD/config/try_umount.txt")" "# umount"

# 非法 config：整体拒绝，已有文件不被破坏
bad_cfg=$(printf "auto_load=1 MODDIR=/tmp/evil\n")
bad=$(make_bundle "$bad_cfg" "/x" "y" "z" "a" "b")
chk "非法 config 被拒" "$(run_bundle "$bad")" "rejected: config: line 1: whitespace in value"
chk "拒绝后 config 未被破坏" "$(grep -c "^auto_load=1$" "$MOD/config/config.ini")" "1"
chk "拒绝后 sus_path 未被破坏" "$(cat "$MOD/config/sus_path.txt")" "/data/adb"

# 段数不足：仍按顺序解析，但不应写入垃圾
short=$(printf "%s|%s" "$(b64 "auto_load=1")" "$(b64 "/p")" | base64 | tr -d "\n")
chk "段数不足被拒绝" "$(run_bundle "$short")" "rejected: expect 6 segments, got 2"

# 非 base64
chk "非法 base64 被拒" "$(run_bundle "!!!notbase64!!!")" "invalid base64"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"