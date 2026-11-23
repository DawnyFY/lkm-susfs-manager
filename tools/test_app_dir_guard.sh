#!/bin/sh
# 回归：系统 App 安装目录不能进 sus_path（会造成「安装记录与 APK 不符」）
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi

TMP=$(mktemp -d)
MOD="$TMP/mod"
mkdir -p "$MOD/state" "$MOD/config"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

MODDIR="$MOD" . "$REPO/common.sh" >/dev/null 2>&1
cls() { if is_app_install_dir "$1"; then echo app; else echo other; fi; }

# 拦截：根 + 一级包名
chk "/product/priv-app/GmsCore"      "$(cls /product/priv-app/GmsCore)"      "app"
chk "/system/priv-app/GmsCore"       "$(cls /system/priv-app/GmsCore)"       "app"
chk "/system/app/Vending"            "$(cls /system/app/Vending)"            "app"
chk "/system_ext/priv-app/Foo"       "$(cls /system_ext/priv-app/Foo)"       "app"
chk "/vendor/app/Bar"                "$(cls /vendor/app/Bar)"                "app"
chk "/odm/app/Baz"                   "$(cls /odm/app/Baz)"                   "app"

# 放行：包内更深层、普通数据目录、/data/adb
chk "/product/priv-app/GmsCore/m"            "$(cls /product/priv-app/GmsCore/m)"            "other"
chk "/product/priv-app/GmsCore/m/independent/AndroidPlatformServices.apk" \
    "$(cls /product/priv-app/GmsCore/m/independent/AndroidPlatformServices.apk)" "other"
chk "/data/data/com.google.android.gms"      "$(cls /data/data/com.google.android.gms)"      "other"
chk "/data/adb"                              "$(cls /data/adb)"                              "other"
chk "/system/app"                            "$(cls /system/app)"                            "other"
chk "/product/priv-app"                      "$(cls /product/priv-app)"                      "other"

# 结构断言：apply.sh 里两处调用 + hide_gapps 不再列安装目录
S="$REPO/apply.sh"
chk "用户循环有守卫" "$(grep -c 'is_app_install_dir "\$path"' "$S")" "1"
chk "add_sus_path_safe 有守卫" "$(grep -c 'is_app_install_dir "\$_p"' "$S")" "1"
chk "hide_gapps 不再隐藏安装目录" "$(grep -c '/product/priv-app/GmsCore' "$S")" "0"
chk "hide_gapps 改隐藏数据目录" "$(grep -c '/data/data/com.google.android.gms' "$S")" "1"
chk "跳过时撤销旧规则" "$(grep -c '_skip_revert' "$S" | awk '{print ($1>=3)?"yes":"no"}')" "yes"

rm -rf "$TMP"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"
