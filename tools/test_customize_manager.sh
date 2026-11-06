#!/bin/sh
# 离线测试：customize.sh 的管理器识别与标签（KernelSU / Magisk / APatch / 未知）
set -u
REPO="$1"
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }
has() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }

MOD="$TMP/mod"
mkdir -p "$MOD/lib" "$MOD/bin" "$TMP/fakebin"
printf "id=susfs_allinone\nname=x\nversion=1.2.2\nversionCode=14\ndescription=d\n" > "$MOD/module.prop"
printf 'fake-ko\n' > "$MOD/lib/susfs_guard_lkm-android15-6.6.ko"
: > "$MOD/bin/susfs_insmod"
: > "$MOD/bin/ksu_susfs_good"
cat > "$MOD/kmi.sh" <<'EOF'
select_kmi() { echo android15-6.6; }
guess_kmis() { :; }
list_kmis() { echo android15-6.6; }
EOF
# 伪造 awk（让 /proc/version 解析为空）与 cat（提供 osrelease），避免依赖宿主机内核
printf "#!/bin/sh\nexit 0\n" > "$TMP/fakebin/awk"
printf "#!/bin/sh\necho 6.6.77-android15-8-gtest\n" > "$TMP/fakebin/cat"
chmod +x "$TMP/fakebin/awk" "$TMP/fakebin/cat"

run_case() {
    # $@ = KEY=VALUE...
    env -i PATH="$TMP/fakebin:/usr/bin:/bin" MODPATH="$MOD" ARCH=arm64 "$@" \
        sh -c 'ui_print(){ printf "UI:%s\n" "$1"; }; abort(){ printf "ABORT:%s\n" "$1"; exit 7; }; set_perm(){ :; }; set_perm_recursive(){ :; }; . "$0/customize.sh"' "$REPO" 2>&1
}

# 1. KernelSU
out=$(run_case KSU=true KSU_VER=4.3.0); rc=$?
chk "KSU 安装成功" "$rc" "0"
chk "KSU 标签" "$(has "$out" "管理器: 4.3.0")" "yes"

# 2. Magisk
out=$(run_case MAGISK_VER=27.0 MAGISK_VER_CODE=27000); rc=$?
chk "Magisk 安装成功" "$rc" "0"
chk "Magisk 标签" "$(has "$out" "管理器: Magisk 27.0")" "yes"

# 3. APatch（会同时带 MAGISK_VER_CODE=27000，必须优先识别成 APatch）
out=$(run_case APATCH=true APATCH_VER=10672 KERNELPATCH=true MAGISK_VER=27.0 MAGISK_VER_CODE=27000); rc=$?
chk "APatch 安装成功" "$rc" "0"
chk "APatch 标签" "$(has "$out" "管理器: APatch 10672")" "yes"
chk "APatch 不误标成 Magisk" "$(has "$out" "管理器: Magisk")" "no"
chk "APatch 打印未验证提示" "$(has "$out" "APatch 未实机验证")" "yes"

# 4. 未知管理器：必须 abort
out=$(run_case); rc=$?
chk "未知管理器被拒" "$rc" "7"
chk "拒绝信息含 APatch" "$(has "$out" "APatch")" "yes"

rm -rf "$TMP"
exit "$fail"
