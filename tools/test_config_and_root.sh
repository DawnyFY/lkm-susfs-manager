#!/bin/sh
# 离线测试：注释解析、root_family 运行时判定、锁接管写 boot_id
set -u
REPO="$1"
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

printf "test-boot\n" > "$TMP/bid"
out=$( ( MODDIR="$M"; PROC_BOOT_ID_FILE="$TMP/bid"; . "$REPO/common.sh"; lock_acquire "$TMP/lk" 900; printf "999 old-boot\n" > "$TMP/lk/pid"; lock_acquire "$TMP/lk" 900; echo "second=$?"; cat "$TMP/lk/pid" ) )
chk "跨 boot 旧锁可接管" "$(printf "%s\n" "$out" | sed -n "s/^second=//p")" "0"
chk "接管后 pid 记录带 boot_id" "$(printf "%s\n" "$out" | sed -n "2p" | awk "{print \$2}")" "test-boot"

rm -rf "$TMP"
exit "$fail"
