#!/bin/sh
# 离线测试：能力判定只读，不调用会改状态的命令；实测失败后降级
set -u
REPO="$1"
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1  expect=[$3] got=[$2]"; fail=1; fi; }

cat > "$TMP/ksu_susfs" <<"EOF"
#!/bin/sh
case "$1" in
  show)
    case "$2" in
      version) echo "v2.3.0";;
      enabled_features)
        [ "$FAKE_FEATURES" = "both" ] && printf "%s\n" CONFIG_KSU_SUSFS_SUS_MOUNT CONFIG_KSU_SUSFS_TRY_UMOUNT
        [ "$FAKE_FEATURES" = "none" ] && echo "SUSFS_LKM_MODULES";;
    esac;;
  add_sus_mount|add_try_umount) echo "CALLED" >> "$FAKE_CALLS";;
esac
EOF
chmod 755 "$TMP/ksu_susfs"
MODDIR="$TMP"; mkdir -p "$TMP/config" "$TMP/state"; SUSFS_PATH_NODE="$TMP/node"
. "$REPO/common.sh"
select_susfs_bin() { echo "$TMP/ksu_susfs"; }
export FAKE_CALLS="$TMP/calls" FAKE_FEATURES

FAKE_FEATURES=both; : > "$FAKE_CALLS"
caps_refresh
chk "特性位齐全判支持" "$(grep -c "^sus_mount=1$" "$STATE/caps")" "1"
chk "记录来源为 feature" "$(grep -c "^sus_mount_src=feature$" "$STATE/caps")" "1"
chk "判定过程没有调用会改状态的命令" "$(wc -l < "$FAKE_CALLS" | tr -d " ")" "0"

FAKE_FEATURES=none; : > "$FAKE_CALLS"
caps_refresh
chk "无特性位判不支持" "$(grep -c "^try_umount=0$" "$STATE/caps")" "1"

FAKE_FEATURES=both; caps_refresh
caps_downgrade sus_mount
chk "实测失败后降级为 0" "$(grep -c "^sus_mount=0$" "$STATE/caps")" "1"
chk "来源改为 probe" "$(grep -c "^sus_mount_src=probe$" "$STATE/caps")" "1"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"