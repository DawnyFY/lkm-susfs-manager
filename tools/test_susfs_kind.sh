#!/bin/sh
# 离线测试：内核侧 SUSFS 探测（LKM 标记 / 内核内置握手 / 无）
set -u
REPO="$1"
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }
MOD="$TMP/mod"; mkdir -p "$MOD"
PROC="$TMP/proc"; mkdir -p "$PROC"
: > "$PROC/susfs_path"
GOOD="$TMP/ksu_susfs_good"; BAD="$TMP/ksu_susfs_bad"
printf '#!/bin/sh\n[ "$1" = show ] && [ "$2" = version ] && { echo "v2.3.0"; exit 0; }\n[ "$1" = show ] && [ "$2" = variant ] && { echo "GKI"; exit 0; }\nexit 1\n' > "$GOOD"
printf '#!/bin/sh\nexit 1\n' > "$BAD"
chmod +x "$GOOD" "$BAD"

kind() {
  # 注意：替身函数里的 $1/$2 是替身自己的参数，必须先存到全局变量
  ( _SUSFS_KIND=""
    MODDIR="$MOD"
    SUSFS_TEST_HOOK=1
    SUSFS_PROC_DIR="$PROC"
    _k_lkm="$1"; _k_active="$2"; _k_backup="$3"
    . "$REPO/common.sh"
    if [ "$_k_lkm" = "1" ]; then lkm_present() { return 0; }; else lkm_present() { return 1; }; fi
    if [ -n "$_k_active" ]; then find_susfs_bin() { printf "%s" "$_k_active"; }; else find_susfs_bin() { return 0; }; fi
    if [ -n "$_k_backup" ]; then find_susfs_backup() { printf "%s" "$_k_backup"; }; else find_susfs_backup() { return 0; }; fi
    susfs_kernel_kind )
}
ready() {
  ( _SUSFS_KIND=""
    MODDIR="$MOD"
    SUSFS_TEST_HOOK=1
    SUSFS_PROC_DIR="$PROC"
    _r_active="$1"
    . "$REPO/common.sh"
    lkm_present() { return 1; }
    if [ -n "$_r_active" ]; then find_susfs_bin() { printf "%s" "$_r_active"; }; else find_susfs_bin() { return 0; }; fi
    find_susfs_backup() { return 0; }
    if susfs_kernel_ready; then echo yes; else echo no; fi )
}

chk "LKM 标记存在 → lkm" "$(kind 1 "" "")" "lkm"
chk "无标记但工具握手成功 → builtin" "$(kind 0 "$GOOD" "")" "builtin"
# 无 /proc 节点时不能仅凭工具输出判定 builtin
PROC2="$TMP/proc2"; mkdir -p "$PROC2"
kind_nonode() {
  ( _SUSFS_KIND=""
    MODDIR="$MOD"
        SUSFS_TEST_HOOK=1
    SUSFS_PROC_DIR="$PROC2"
    . "$REPO/common.sh"
    lkm_present() { return 1; }
    find_susfs_bin() { printf "%s" "$GOOD"; }
    find_susfs_backup() { return 0; }
    susfs_kernel_kind )
}
chk "工具输出但无 /proc 节点 → 不判 builtin" "$(kind_nonode)" "none"
# 工具 exit 0 但版本/特性输出为空 → 不判 builtin
EMPTYTOOL="$TMP/empty_tool"; printf '#!/bin/sh\nexit 0\n' > "$EMPTYTOOL"; chmod +x "$EMPTYTOOL"
chk "工具 exit 0 但无有效输出 → none" "$(kind 0 "$EMPTYTOOL" "")" "none"
# 工具能输出 variant、但 version 查询失败 → 不判 builtin
HALFTOOL="$TMP/half_tool"; printf '#!/bin/sh\n[ "$1" = show ] && [ "$2" = variant ] && { echo GKI; exit 0; }\nexit 1\n' > "$HALFTOOL"; chmod +x "$HALFTOOL"
chk "variant 有但 version 失败 → none" "$(kind 0 "$HALFTOOL" "")" "none"
chk "无标记、无工具 → none" "$(kind 0 "" "")" "none"
chk "工具握手失败 → none" "$(kind 0 "$BAD" "")" "none"
chk "LKM 标记优先于握手" "$(kind 1 "$GOOD" "")" "lkm"
chk "内置时 ready=yes" "$(ready "$GOOD")" "yes"
chk "都没有时 ready=no" "$(ready "")" "no"

rm -rf "$TMP"
exit "$fail"
