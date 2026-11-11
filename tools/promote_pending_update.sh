#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# 不重启就把 modules_update 里已安装的新版本就地补齐到活动模块目录（临时 root 场景）。
# 用法（root）：sh promote_pending_update.sh [模块id，默认 susfs_allinone]
# 说明：只补运行期文件，config/ 与 state/ 保持用户现有内容；最后清掉 update 标记，
#       管理器才会重新显示「执行 / 打开 WebUI」按钮。
ID=${1:-susfs_allinone}
SRC=/data/adb/modules_update/$ID
DST=/data/adb/modules/$ID

[ -d "$SRC" ] || { echo "没有待生效的更新：$SRC"; exit 0; }
[ -d "$DST" ] || { echo "模块不存在：$DST"; exit 1; }

echo "== 备份 =="
tar -czf "/data/local/tmp/$ID.backup.tgz" -C /data/adb/modules "$ID" || { echo "备份失败，停止"; exit 1; }
ls -l "/data/local/tmp/$ID.backup.tgz"

echo "== 补齐文件 =="
for f in $(cd "$SRC" && ls -A); do
    case "$f" in
        config|state) echo "跳过 $f"; continue ;;
    esac
    rm -rf "$DST/$f"
    cp -a "$SRC/$f" "$DST/$f" || { echo "拷贝失败：$f"; exit 1; }
    echo "已更新 $f"
done

rm -rf "$SRC"
rmdir /data/adb/modules_update 2>/dev/null
# 就地升级也要清掉上一版本遗留的失败/暂停/守卫，否则新版本首启不会尝试新加载路径
rm -f "$DST/state/autoload_paused" "$DST/state/fail_count" "$DST/state/loading" "$DST/state/boot_guard" 2>/dev/null
echo "已清理旧 autoload_paused/fail_count/loading/boot_guard"
# 清掉「待更新」标记，否则管理器一直隐藏 执行 / WebUI 按钮
rm -f "$DST/update"
chmod 0755 "$DST"/*.sh "$DST/bin"/* 2>/dev/null

echo "== 完整性校验 =="
MODDIR="$DST"
export MODDIR
. "$DST/common.sh" 2>/dev/null
_cf 2>/dev/null
rc=$?
echo "_cf rc=$rc（0=通过）"
if [ "$rc" != "0" ]; then
    echo "[!] 校验未通过：把备份还原回去，别继续用"
    exit 1
fi
echo "完成：管理器里重开模块页应出现「打开」按钮"
