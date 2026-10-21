#!/system/bin/sh
# Read-only cold-boot verification for SUSFS 管理器.
# Usage (on the device, after re-rooting):
#   sh /data/local/tmp/verify_after_boot.sh [expected_user_rules]
# Default expected user rules: 8.
# This script never loads/unloads the LKM and never applies rules.

MODDIR=${MODDIR:-/data/adb/modules/susfs_allinone}
UPDATE=/data/adb/modules_update/susfs_allinone
EXPECTED=${1:-8}
FAIL=0
BIN=""

echo "===== SUSFS 管理器 cold-boot verification ====="
date
echo "[i] model: $(getprop ro.product.model)"
echo "[i] android: $(getprop ro.build.version.release) / $(getprop ro.build.display.id)"
echo "[i] selinux: $(getenforce 2>/dev/null)"
uname -a

echo
echo "----- module.prop -----"
if [ -f "$MODDIR/module.prop" ]; then
    cat "$MODDIR/module.prop"
else
    echo "missing module.prop"
    FAIL=1
fi

echo
echo "----- status -----"
STATUS=$(sh "$MODDIR/ctl.sh" status 2>&1)
echo "$STATUS"

echo
echo "----- checks -----"
echo "$STATUS" | grep -q '^lkm_present=1$' || { echo "FAIL: lkm_present != 1"; FAIL=1; }
echo "$STATUS" | grep -q "^rules=$EXPECTED$" || { echo "FAIL: rules != $EXPECTED"; FAIL=1; }
echo "$STATUS" | grep -q '^auto_load=1$' || { echo "FAIL: auto_load != 1"; FAIL=1; }
echo "$STATUS" | grep -q '^ksu_bin=ok$' || { echo "FAIL: ksu_bin != ok"; FAIL=1; }
if echo "$STATUS" | grep -q '^root_manager=Unknown$'; then
    echo "FAIL: root_manager is Unknown"
    FAIL=1
fi

PATHS=$(grep -c '^path=' /proc/susfs_path 2>/dev/null)
PATHS=${PATHS:-0}
echo "[i] /proc/susfs_path path lines: $PATHS"
[ "$PATHS" -gt 0 ] || { echo "FAIL: /proc/susfs_path has no path lines"; FAIL=1; }

MARKER=0
for p in /data/adb/ksu/susfs4ksu/logs/susfs_active /data/adb/ap/susfs4ksu/logs/susfs_active /data/adb/susfs4ksu/logs/susfs_active; do
    [ -f "$p" ] && MARKER=1
done
if [ "$MARKER" = "1" ]; then echo "[i] marker: present"; else echo "FAIL: marker missing"; FAIL=1; fi

if [ -d "$UPDATE" ]; then
    echo "FAIL: pending update still exists at $UPDATE (update may not have merged)"
    FAIL=1
else
    echo "[i] pending update: none"
fi

echo
echo "----- paths -----"
grep '^path=' /proc/susfs_path 2>/dev/null | head -n 40

echo
echo "----- load.log (tail) -----"
tail -n 30 "$MODDIR/load.log" 2>/dev/null

echo
echo "----- apply.log (tail) -----"
tail -n 40 "$MODDIR/apply.log" 2>/dev/null

echo
echo "----- old modules (should be disabled/removed after verification) -----"
for m in susfs4ksu susfs_oneshot; do
    if [ -d "/data/adb/modules/$m" ]; then
        if [ -f "/data/adb/modules/$m/disable" ]; then
            echo "$m: installed, disabled"
        else
            echo "$m: installed, ENABLED"
        fi
    else
        echo "$m: not installed"
    fi
done

echo
if [ "$FAIL" = "0" ]; then
    echo "VERIFY_RESULT=OK"
else
    echo "VERIFY_RESULT=FAIL"
fi
exit "$FAIL"
