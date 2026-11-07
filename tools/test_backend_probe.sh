#!/bin/sh
# 离线测试：kernel_config_get（内置 SUSFS 后端契约探测的基础）
set -u
REPO="$1"
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }
M="$TMP/mod"; mkdir -p "$M/state"
GZ="$TMP/config.gz"
printf "CONFIG_MODULES=y\nCONFIG_KALLSYMS_ALL=y\nCONFIG_KSU=y\nCONFIG_KSU_SUSFS=y\n# CONFIG_KSU_SUSFS_SUS_MAP is not set\n" | gzip > "$GZ"
get() { ( MODDIR="$M"; SUSFS_TEST_HOOK=1; CONFIG_GZ_FILE="$GZ"; . "$REPO/common.sh"; kernel_config_get "$1" ); }
chk "读 CONFIG_KSU" "$(get CONFIG_KSU)" "y"
chk "读 CONFIG_KSU_SUSFS" "$(get CONFIG_KSU_SUSFS)" "y"
chk "未开启项返回 n" "$(get CONFIG_KSU_SUSFS_SUS_MAP)" "n"
chk "不存在项返回 absent" "$(get CONFIG_KSU_SUSFS_SUS_PATH)" "absent"
printf "plain text, not gzip\n" > "$TMP/bad.gz"
getbad() { ( MODDIR="$M"; SUSFS_TEST_HOOK=1; CONFIG_GZ_FILE="$TMP/bad.gz"; . "$REPO/common.sh"; kernel_config_get CONFIG_KSU ); }
chk "config.gz 不可解析时返回 unknown" "$(getbad)" "unknown"
rm -f "$GZ"
getmissing() { ( MODDIR="$M"; SUSFS_TEST_HOOK=1; CONFIG_GZ_FILE="$GZ"; . "$REPO/common.sh"; kernel_config_get CONFIG_KSU ); }
chk "config.gz 不存在时返回 unknown" "$(getmissing)" "unknown"
chk "backend_probe 已接入 ctl.sh" "$(grep -c "^    backend_probe)" "$REPO/ctl.sh")" "1"
rm -rf "$TMP"
exit "$fail"
