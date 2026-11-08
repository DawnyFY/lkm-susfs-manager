#!/bin/sh
# 离线测试：注释解析、root_family 运行时判定、锁接管写 boot_id
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }
M="$TMP/mod"; mkdir -p "$M/state"

cfg() { ( MODDIR="$M"; . "$REPO/common.sh"; eval "$1" ) }
chk "行内空格+# 视为注释" "$(cfg 'strip_comment "  /data/adb # 注释 "')" "/data/adb"
chk "路径里的 # 保留" "$(cfg 'strip_comment "/sdcard/a#b"')" "/sdcard/a#b"
chk "整行注释为空" "$(cfg 'strip_comment "# whole line"')" ""

FB="$TMP/bin"; mkdir -p "$FB"
printf "#!/bin/sh\n[ \"\$1\" = magiskd ] && exit 0\nexit 1\n" > "$FB/pidof"; chmod +x "$FB/pidof"
out=$( ( PATH="$FB:$PATH"; MODDIR="$M"; . "$REPO/common.sh"; root_family ) )
chk "有 magiskd 时判 Magisk（目录残留不影响）" "$out" "Magisk"
printf "#!/bin/sh\nexit 1\n" > "$FB/pidof"
out=$( ( PATH="$FB:$PATH"; MODDIR="$M"; . "$REPO/common.sh"; root_family ) )
chk "无进程时按目录判定（本机无 /data/adb → Unknown）" "$out" "Unknown"

# kernelpatch_present：用 KERNELPATCH_MARKER_DIR 模拟 /data/adb/ap
mkdir -p "$TMP/apmark"
: > "$TMP/apmark/package_config"
out=$( ( MODDIR="$M"; SUSFS_TEST_HOOK=1; KERNELPATCH_MARKER_DIR="$TMP/apmark"; . "$REPO/common.sh"; kernelpatch_present && echo yes || echo no ) )
chk "有 APatch 标记目录 → 进入共存模式" "$out" "yes"
out=$( ( MODDIR="$M"; SUSFS_TEST_HOOK=1; KERNELPATCH_MARKER_DIR="$TMP/nomark"; PATH="$FB:$PATH"; . "$REPO/common.sh"; kernelpatch_present && echo yes || echo no ) )
chk "无标记且非 APatch → 非共存模式" "$out" "no"
out=$( ( MODDIR="$M"; SUSFS_TEST_HOOK=1; KERNELPATCH_MARKER_DIR="$TMP/apmark"; . "$REPO/common.sh"; coexist_disable_avc_spoof && echo disable || echo keep ) )
chk "共存模式下禁用 avc_spoof" "$out" "disable"

printf "test-boot\n" > "$TMP/bid"
out=$( ( MODDIR="$M"; PROC_BOOT_ID_FILE="$TMP/bid"; . "$REPO/common.sh"; lock_acquire "$TMP/lk" 900; printf "999 old-boot\n" > "$TMP/lk/pid"; lock_acquire "$TMP/lk" 900; echo "second=$?"; cat "$TMP/lk/pid" ) )
chk "跨 boot 旧锁可接管" "$(printf "%s\n" "$out" | sed -n "s/^second=//p")" "0"
chk "接管后 pid 记录带 boot_id" "$(printf "%s\n" "$out" | sed -n "2p" | awk "{print \$2}")" "test-boot"

rm -rf "$TMP"
exit "$fail"
