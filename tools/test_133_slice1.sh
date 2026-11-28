#!/bin/sh
# 1.3.3 首个切片：配置补键（只加不覆盖）+ dmesg 崩溃取证（pstore 空时的唯一证据）
set -u
REPO="$1"
[ -f "$REPO/module/module.prop" ] && REPO="$REPO/module"
export REPO
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

chk "有 cfg_ensure_missing_keys" "$(grep -c "^cfg_ensure_missing_keys()" "$REPO/common.sh")" "1"
chk "apply 调用补键" "$(grep -c "^cfg_ensure_missing_keys$" "$REPO/apply.sh")" "1"
chk "有 dmesg_crash_capture" "$(grep -c "^dmesg_crash_capture()" "$REPO/common.sh")" "1"
chk "service 调用取证" "$(grep -c "dmesg_crash_capture" "$REPO/service.sh")" "1"

# 行为 1：老配置缺键 → 追加默认值；已有值不被覆盖
T=$(mktemp -d); mkdir -p "$T/config" "$T/state"
printf "auto_load=1\nwatchdog_minutes=7\n" > "$T/config/config.ini"
printf "# 注释\nauto_load=1\nsusfs_log=0\nwatchdog_minutes=0\nnew_key=42\n" > "$T/config/config.ini.default"
printf '. "$REPO/common.sh" >/dev/null 2>&1\ncfg_ensure_missing_keys\n' > "$T/run.sh"
out=$(MODDIR="$T" sh "$T/run.sh" 2>&1)
chk "补了 2 个缺失键" "$(printf "%s" "$out" | grep -c "配置补齐 2 个新键")" "1"
chk "susfs_log 已补" "$(grep -c "^susfs_log=0$" "$T/config/config.ini")" "1"
chk "new_key 已补" "$(grep -c "^new_key=42$" "$T/config/config.ini")" "1"
chk "用户值 watchdog=7 未被覆盖" "$(grep -c "^watchdog_minutes=7$" "$T/config/config.ini")" "1"
chk "没有写入重复的 auto_load" "$(grep -c "^auto_load=" "$T/config/config.ini")" "1"
chk "没有把注释抄进去" "$(grep -c "^# 注释" "$T/config/config.ini")" "0"

# 行为 2：dmesg 有告警 → 生成 crash_dmesg.txt；无告警 → 不生成
cat > "$T/fake_dmesg_hit" <<'EOS'
#!/bin/sh
echo "[  1.0] ------------[ cut here ]------------"
echo "[  1.1] WARNING: CPU: 4 PID: 1 at kernel/workqueue.c:1808 __queue_work+0x3f8/0x610"
echo "[  1.2] Call trace:"
echo "[  1.3]  __queue_work+0x3f8/0x610"
EOS
cat > "$T/fake_dmesg_clean" <<'EOS'
#!/bin/sh
echo "[  1.0] Booting Linux"
EOS
chmod +x "$T/fake_dmesg_hit" "$T/fake_dmesg_clean" 2>/dev/null || true
printf '. "$REPO/common.sh" >/dev/null 2>&1\ndmesg_crash_capture\n' > "$T/run2.sh"
out2=$(MODDIR="$T" DMESG_BIN="$T/fake_dmesg_hit" sh "$T/run2.sh" 2>&1)
chk "有告警时提示" "$(printf "%s" "$out2" | grep -c "已存 state/crash_dmesg.txt")" "1"
chk "文件已生成" "$([ -s "$T/state/crash_dmesg.txt" ] && echo yes || echo no)" "yes"
chk "文件含 WARNING 行" "$(grep -c "WARNING: CPU" "$T/state/crash_dmesg.txt")" "1"
chk "文件含调用栈" "$([ "$(grep -c "__queue_work" "$T/state/crash_dmesg.txt")" -ge 1 ] && echo yes || echo no)" "yes"
rm -f "$T/state/crash_dmesg.txt"
out3=$(MODDIR="$T" DMESG_BIN="$T/fake_dmesg_clean" sh "$T/run2.sh" 2>&1)
chk "无告警时不生成文件" "$([ -e "$T/state/crash_dmesg.txt" ] && echo yes || echo no)" "no"
chk "无告警时无提示" "$(printf "%s" "$out3" | grep -c "crash_dmesg")" "0"

rm -rf "$T"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "HAS FAILURE"
exit "$fail"