#!/bin/sh
# 离线测试：pid_guard.sh 的加载 / 卸载 / 失败可见 / 自隐藏
# 覆盖 G4（enabled=0 主动卸载）、G5（insmod 失败写入状态）、G6（装载后写隐藏列表）
set -u
REPO="$1"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

MOD="$TMP/mod"
SYSMOD="$TMP/sysmod"
PROCMOD="$TMP/proc_modules"
HIDE="$TMP/hide_modules"
ARGS="$TMP/ksud.args"
mkdir -p "$MOD/config" "$MOD/state" "$MOD/lib/pid_guard/6.6" "$SYSMOD" "$TMP/bin"
cp "$REPO/pid_guard.sh" "$MOD/pid_guard.sh"
: > "$MOD/lib/pid_guard/6.6/generic_pid_guard.ko"
: > "$PROCMOD"
: > "$HIDE"
: > "$ARGS"

cat > "$TMP/bin/ksud" <<'EOF'
#!/bin/sh
echo "ksud $*" >> "$KSUD_ARGS"
[ "$1" = "insmod" ] || exit 1
if [ "${FAKE_KSUD_RC:-0}" = "0" ]; then mkdir -p "$PG_SYS_MOD/generic_pid_guard"; fi
exit "${FAKE_KSUD_RC:-0}"
EOF

cat > "$TMP/bin/rmmod" <<'EOF'
#!/bin/sh
echo "rmmod $*" >> "$KSUD_ARGS"
if [ "${FAKE_RMMOD_RC:-0}" = "0" ]; then rm -rf "$PG_SYS_MOD/$1"; fi
exit "${FAKE_RMMOD_RC:-0}"
EOF
chmod +x "$TMP/bin/ksud" "$TMP/bin/rmmod"

seed() {
    printf 'enabled=%s\ntarget_uids=99000-99999\ntarget_comms=probe-*,canProbe*,ivecheck*\nexclude_comms=nqiunativecheck\n' "$1" \
        > "$MOD/config/pid_guard.conf"
    rm -f "$MOD/state/pid_guard.status" "$MOD/load.log" "$MOD/state/pid_guard.conf_hash"
    : > "$ARGS"
}
# 不重置配置与 conf_hash，用于验证连续 apply 的幂等与参数变更重载
run_keep() {
    : > "$ARGS"
    env PG_SYS_MOD="$SYSMOD" PG_PROC_MODULES="$PROCMOD" PG_HIDE_LIST="$HIDE" PG_KSUD="$TMP/bin/ksud" \
        PATH="$TMP/bin:$PATH" KSUD_ARGS="$ARGS" \
        FAKE_KSUD_RC="${FAKE_KSUD_RC:-0}" FAKE_RMMOD_RC="${FAKE_RMMOD_RC:-0}" \
        sh "$MOD/pid_guard.sh" "$1" >/dev/null 2>&1
    echo $?
}
# $1=enabled  $2=KMI，其余通过 FAKE_*/PG_* 环境变量控制
run() {
    seed "$1"
    env PG_SYS_MOD="$SYSMOD" PG_PROC_MODULES="$PROCMOD" PG_HIDE_LIST="$HIDE" PG_KSUD="$TMP/bin/ksud" \
        PATH="$TMP/bin:$PATH" KSUD_ARGS="$ARGS" \
        FAKE_KSUD_RC="${FAKE_KSUD_RC:-0}" FAKE_RMMOD_RC="${FAKE_RMMOD_RC:-0}" \
        sh "$MOD/pid_guard.sh" "$2" >/dev/null 2>&1
    echo $?
}
status() { grep -m1 '^result=' "$MOD/state/pid_guard.status" 2>/dev/null | cut -d= -f2; }
loghas() { grep -q "$1" "$MOD/load.log" 2>/dev/null && echo yes || echo no; }
ksud_calls() { grep -c "^ksud " "$ARGS" 2>/dev/null | head -1; }
hide_has() { grep -qx "add generic_pid_guard" "$HIDE" 2>/dev/null && echo yes || echo no; }
reset() { rm -rf "$SYSMOD"/*; : > "$PROCMOD"; : > "$HIDE"; : > "$ARGS"; }

# 1. enabled=0 且未加载：不碰 rmmod/ksud
reset
FAKE_KSUD_RC=0 FAKE_RMMOD_RC=0
chk "enabled=0 未加载 返回 0" "$(run 0 android15-6.6)" "0"
chk "enabled=0 未加载 结果 skipped" "$(status)" "skipped"
chk "enabled=0 未加载 不调用 ksud" "$(ksud_calls)" "0"

# 2. enabled=0 且已加载：主动卸载（G4）
reset
mkdir -p "$SYSMOD/generic_pid_guard"
chk "enabled=0 已加载 返回 0" "$(run 0 android15-6.6)" "0"
chk "enabled=0 已加载 结果 unloaded" "$(status)" "unloaded"
chk "enabled=0 已加载 目录消失" "$([ -d "$SYSMOD/generic_pid_guard" ] && echo no || echo yes)" "yes"

# 3. enabled=0 卸载失败：状态可见（G5 同源）
reset
mkdir -p "$SYSMOD/generic_pid_guard"
FAKE_KSUD_RC=1 FAKE_RMMOD_RC=1
chk "卸载失败 返回 1" "$(run 0 android15-6.6)" "1"
chk "卸载失败 结果 unload_failed" "$(status)" "unload_failed"
FAKE_KSUD_RC=0
FAKE_RMMOD_RC=0

# 4. enabled=1 但没有该 KMI 的 ko：跳过且不报错
reset
chk "缺 ko 返回 0" "$(run 1 android14-6.1)" "0"
chk "缺 ko 结果 no_ko" "$(status)" "no_ko"
chk "缺 ko 日志有说明" "$(loghas 'no ko for KMI')" "yes"

# 5. enabled=1 首次加载：KMI 映射 + 装载后自隐藏（G6）
reset
chk "首次加载 返回 0" "$(run 1 android15-6.6)" "0"
chk "首次加载 结果 ok" "$(status)" "ok"
chk "首次加载 走 6.6 的 ko" "$(grep -c 'lib/pid_guard/6.6/generic_pid_guard.ko' "$ARGS")" "1"
chk "首次加载 传递三个参数" "$(grep -c 'target_uids=99000-99999 target_comms=probe-\*,canProbe\*,ivecheck\* exclude_comms=nqiunativecheck' "$ARGS")" "1"
chk "首次加载 写隐藏列表" "$(hide_has)" "yes"
chk "首次加载 日志记录已加载" "$(loghas 'pid_guard 已加载')" "yes"
chk "首次加载 不再重复 ksud 的原话" "$(loghas 'Loaded kernel module')" "no"

# 6. 同一份配置再次 apply：幂等，不重复 insmod
reset
chk "同配置首次 返回 0" "$(run 1 android15-6.6)" "0"
chk "同配置再次 返回 0" "$(run_keep android15-6.6)" "0"
chk "同配置再次 不调用 ksud" "$(ksud_calls)" "0"
chk "同配置再次 仍写隐藏列表" "$(hide_has)" "yes"
chk "同配置再次 结果 ok" "$(status)" "ok"

# 6b. 参数变更：就地重载（先卸载再按新参数 insmod），不必重启
printf 'enabled=1\ntarget_uids=98000-98999\ntarget_comms=probe-*\nexclude_comms=nqiunativecheck\n' \
    > "$MOD/config/pid_guard.conf"
chk "参数变更 返回 0" "$(run_keep android15-6.6)" "0"
chk "参数变更 只有一次 insmod" "$(ksud_calls)" "1"
chk "参数变更 覆盖旧模块" "$(grep -c '^rmmod generic_pid_guard' "$ARGS")" "1"
chk "参数变更 使用新参数" "$(grep -c 'target_uids=98000-98999' "$ARGS")" "1"
chk "参数变更 结果 ok" "$(status)" "ok"

# 7. insmod 失败：写入 failed 而不是静默吞掉（G5）
reset
FAKE_KSUD_RC=1
chk "insmod 失败 返回 1" "$(run 1 android15-6.6)" "1"
chk "insmod 失败 结果 failed" "$(status)" "failed"
chk "insmod 失败 日志可见" "$(loghas 'insmod 失败')" "yes"
chk "insmod 失败 不写隐藏列表" "$(hide_has)" "no"
chk "insmod 失败 不留 conf_hash" "$([ -f "$MOD/state/pid_guard.conf_hash" ] && echo yes || echo no)" "no"
FAKE_KSUD_RC=0

# 8. 没有配置文件：静默退出
reset
rm -f "$MOD/config/pid_guard.conf"
env PG_SYS_MOD="$SYSMOD" PG_PROC_MODULES="$PROCMOD" PG_HIDE_LIST="$HIDE" PG_KSUD="$TMP/bin/ksud" \
    PATH="$TMP/bin:$PATH" KSUD_ARGS="$ARGS" sh "$MOD/pid_guard.sh" android15-6.6 >/dev/null 2>&1
chk "无配置 返回 0" "$?" "0"

# 9. 配置写入校验（pid_guard_ctl.sh）：空格 / 裸 * / 元字符 / 非法 enabled 都要拒绝
cp "$REPO/pid_guard_ctl.sh" "$MOD/pid_guard_ctl.sh"
b64() { printf '%s' "$1" | base64 | tr -d '\n'; }
setpg() { sh "$MOD/pid_guard_ctl.sh" set_b64 "$(b64 "$1")" 2>&1; }
good='enabled=1
target_uids=99000-99999
target_comms=probe-*,canProbe*
exclude_comms=nqiunativecheck'
chk "合法配置写入成功" "$(setpg "$good")" "saved"
chk "合法配置已落盘" "$(grep -c '^target_comms=probe-\*,canProbe\*$' "$MOD/config/pid_guard.conf")" "1"
chk "带空格被拒绝" "$(setpg 'enabled=1
target_uids=99000-99999
target_comms=probe-*, canProbe*
exclude_comms=')" "rejected: target_comms illegal char / empty item / space"
chk "拒绝后旧配置未被覆盖" "$(grep -c '^target_comms=probe-\*,canProbe\*$' "$MOD/config/pid_guard.conf")" "1"
chk "裸 * 被拒绝" "$(setpg 'enabled=1
target_uids=99000
target_comms=*
exclude_comms=')" "rejected: comm wildcard * only allowed as a trailing *"
chk "命令替换被拒绝" "$(setpg 'enabled=1
target_uids=99000
target_comms=$(reboot)
exclude_comms=')" "rejected: target_comms illegal char / empty item / space"
chk "UID 里带 * 被拒绝" "$(setpg 'enabled=1
target_uids=99*
target_comms=probe-*
exclude_comms=')" "rejected: target_uids must be digits or digits-digits"
chk "UID 非数字被拒绝" "$(setpg 'enabled=1
target_uids=abc
target_comms=probe-*
exclude_comms=')" "rejected: target_uids must be digits or digits-digits"
chk "UID 与 comm 同时为空被拒绝" "$(setpg 'enabled=1
target_uids=
target_comms=
exclude_comms=')" "rejected: target_uids and target_comms cannot both be empty"
chk "enabled 非法被拒绝" "$(setpg 'enabled=2
target_uids=99000
target_comms=probe-*
exclude_comms=')" "rejected: enabled must be 0 or 1"

# 10. 读取侧：即使有人手改 conf，也不 source、不执行 $(...)
reset
printf 'enabled=1\ntarget_uids=99000-99999\ntarget_comms=$(touch %s/PWNED)\nexclude_comms=\n' "$TMP" \
    > "$MOD/config/pid_guard.conf"
rm -f "$TMP/PWNED"
env PG_SYS_MOD="$SYSMOD" PG_PROC_MODULES="$PROCMOD" PG_HIDE_LIST="$HIDE" PG_KSUD="$TMP/bin/ksud" \
    PATH="$TMP/bin:$PATH" KSUD_ARGS="$ARGS" sh "$MOD/pid_guard.sh" android15-6.6 >/dev/null 2>&1
chk "读取侧不执行命令替换" "$([ -e "$TMP/PWNED" ] && echo yes || echo no)" "no"
chk "读取侧结果 bad_conf" "$(status)" "bad_conf"
chk "读取侧不 insmod" "$(ksud_calls)" "0"

rm -rf "$TMP"
exit "$fail"
