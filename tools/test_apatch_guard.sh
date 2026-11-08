#!/bin/sh
# 离线测试：APatch 防护（强特征判定 / pstore 判据与确认 / 内核预检 / apply 早退不误清守卫）
set -u
REPO="$1"
ROOT="$REPO"
if [ -f "$REPO/module/module.prop" ]; then REPO="$REPO/module"; fi
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

# ---------- 1) kernelpatch_present：只用强特征 ----------
KP="$TMP/ap"; mkdir -p "$KP"
out=$( ( MODDIR="$TMP/m"; CONFIG="$TMP/m/config"; SUSFS_TEST_HOOK=1; KERNELPATCH_MARKER_DIR="$KP"; . "$REPO/common.sh"; kernelpatch_present && echo yes || echo no ) )
chk "只有残留目录 → 不算 APatch" "$out" "no"
: > "$KP/package_config"
out=$( ( MODDIR="$TMP/m"; CONFIG="$TMP/m/config"; SUSFS_TEST_HOOK=1; KERNELPATCH_MARKER_DIR="$KP"; . "$REPO/common.sh"; kernelpatch_present && echo yes || echo no ) )
chk "有 package_config → APatch" "$out" "yes"
rm -f "$KP/package_config"; mkdir -p "$KP/bin"; printf "#!/bin/sh\n" > "$KP/bin/apd"; chmod +x "$KP/bin/apd"
out=$( ( MODDIR="$TMP/m"; CONFIG="$TMP/m/config"; SUSFS_TEST_HOOK=1; KERNELPATCH_MARKER_DIR="$KP"; . "$REPO/common.sh"; kernelpatch_present && echo yes || echo no ) )
chk "有 bin/apd → APatch" "$out" "yes"
out=$( ( MODDIR="$TMP/m"; CONFIG="$TMP/m/config"; KERNELPATCH_MARKER_DIR="$KP"; . "$REPO/common.sh"; kernelpatch_present && echo yes || echo no ) )
chk "未开测试钩子时环境变量无效" "$out" "no"

# ---------- 2) pstore 判据与 crash_ack ----------
PS="$TMP/pstore"; mkdir -p "$PS"; M2="$TMP/m2"; mkdir -p "$M2/state"
run_ps() { ( MODDIR="$M2"; CONFIG="$M2/config"; SUSFS_TEST_HOOK=1; PSTORE_DIR="$PS"; . "$REPO/common.sh"; pstore_crash_suspect && echo yes || echo no ); }
out=$(run_ps); chk "空 pstore → no" "$out" "no"
printf "normal boot\n" > "$PS/console-ramoops-0"; out=$(run_ps); chk "普通日志 → no" "$out" "no"
printf "Kernel panic - not syncing: x\n" > "$PS/console-ramoops-0"; out=$(run_ps); chk "只有 panic 没有模块栈 → no" "$out" "no"
printf "Kernel panic - not syncing: x\nsusfs_guard_lkm: boom\n" > "$PS/console-ramoops-0"; out=$(run_ps); chk "panic + susfs_guard_lkm → yes" "$out" "yes"
printf "normal 2\n" > "$PS/second-file"; printf "Kernel panic\nsusfs_guard_lkm: boom\n" > "$PS/dmesg-ramoops-1"
out=$(run_ps); chk "多文件中任一命中 → yes" "$out" "yes"
( MODDIR="$M2"; CONFIG="$M2/config"; SUSFS_TEST_HOOK=1; PSTORE_DIR="$PS"; . "$REPO/common.sh"; pstore_crash_ack ) || true
out=$(run_ps); chk "crash_ack 后不再命中" "$out" "no"
printf "Kernel panic\nsusfs_guard_lkm: boom\nmore\n" > "$PS/dmesg-ramoops-1"
out=$(run_ps); chk "pstore 内容变化后重新命中" "$out" "yes"

# ---------- 3) kernel_load_preflight ----------
PRE() { ( MODDIR="$M2"; CONFIG="$M2/config"; SUSFS_TEST_HOOK=1; MODULES_DISABLED_FILE="$TMP/msd"; CONFIG_GZ_FILE="$TMP/config.gz"; . "$REPO/common.sh"; kernel_load_preflight ); }
printf "0\n" > "$TMP/msd"; printf "CONFIG_MODULES=y\n# CONFIG_MODULE_SIG_FORCE is not set\n" | gzip > "$TMP/config.gz"
out=$(PRE); chk "正常配置 → 可继续" "$out" ""
printf "1\n" > "$TMP/msd"; out=$(PRE); case "$out" in *modules_disabled*) echo yes ;; *) echo no ;; esac > /tmp/preout 2>/dev/null || true
res=$(PRE >/dev/null 2>&1; echo $?)
chk "modules_disabled=1 → 拒绝" "$res" "1"
printf "0\n" > "$TMP/msd"; printf "# CONFIG_MODULES is not set\n" | gzip > "$TMP/config.gz"
res=$(PRE >/dev/null 2>&1; echo $?); chk "未编译 CONFIG_MODULES → 拒绝" "$res" "1"
printf "CONFIG_MODULES=y\nCONFIG_MODULE_SIG_FORCE=y\n" | gzip > "$TMP/config.gz"
res=$(PRE >/dev/null 2>&1; echo $?); chk "强制签名 → 拒绝" "$res" "1"
printf "not-a-gzip-file\n" > "$TMP/config.gz"
res=$(PRE >/dev/null 2>&1; echo $?); chk "config.gz 不可解析 → 跳过不误杀" "$res" "0"

# ---------- 4) apatch_lkm_allowed ----------
M3="$TMP/m3"; mkdir -p "$M3/config"
out=$( ( MODDIR="$M3"; CONFIG="$M3/config"; . "$REPO/common.sh"; apatch_lkm_allowed && echo yes || echo no ) ); chk "默认不放行" "$out" "no"
: > "$M3/config/allow_lkm_on_kernelpatch"
out=$( ( MODDIR="$M3"; CONFIG="$M3/config"; . "$REPO/common.sh"; apatch_lkm_allowed && echo yes || echo no ) ); chk "标记后放行" "$out" "yes"

# ---------- 5) apply 早退不误清守卫（blocker 回归） ----------
build_apply() { # $1=目标目录
    M="$1"; mkdir -p "$M/state" "$M/config"
    printf "description=test\n" > "$M/module.prop"
    cat > "$M/common.sh" <<'STUB'
lock_acquire() { return 0; }
lock_release() { :; }
file_older_than() { return 0; }
restore_config_if_missing() { :; }
ensure_skip_hide_file() { :; }
cfg_ensure() { :; }
cfg_load() { :; }
root_family() { echo TEST; }
kernelpatch_present() { [ "${TEST_KP:-0}" = "1" ]; }
coexist_disable_avc_spoof() { kernelpatch_present; }
pstore_crash_suspect() { [ "${TEST_PSTORE:-0}" = "1" ]; }
pause_autoload() { : > "$STATE/autoload_paused"; }
autoload_paused() { [ -f "$STATE/autoload_paused" ]; }
boot_guard_path() { printf "%s" "$STATE/boot_guard"; }
_cf_run() { return 0; }
susfs_kernel_ready() { [ "${TEST_READY:-0}" = "1" ]; }
apatch_lkm_allowed() { [ "${TEST_ALLOW:-0}" = "1" ]; }
STUB
    sed "s#/data/adb/modules/susfs_allinone#$M#g" "$REPO/apply.sh" > "$M/apply_under_test.sh"
}
run_apply() { ( M="$1"; shift; TEST_KP="$1" TEST_PSTORE="$2" TEST_READY="$3" TEST_ALLOW="$4" AUTOLOAD="$5" sh "$M/apply_under_test.sh" >/dev/null 2>&1; echo $? ); }

A="$TMP/a1"; build_apply "$A"; : > "$A/state/boot_guard"
rc=$(run_apply "$A" 0 1 0 0 1); chk "pstore 命中时 auto apply 返回 3" "$rc" "3"
chk "pstore 命中时保留 boot_guard" "$([ -f "$A/state/boot_guard" ] && echo yes || echo no)" "yes"
chk "pstore 命中时写下暂停标记" "$([ -f "$A/state/autoload_paused" ] && echo yes || echo no)" "yes"
chk "pstore 命中时 apply_result=skipped" "$(cat "$A/state/apply_result" 2>/dev/null)" "skipped"

A="$TMP/a2"; build_apply "$A"
rc=$(run_apply "$A" 1 0 0 0 1); chk "APatch 未放行 auto apply 退出 0（跳过）" "$rc" "0"
chk "APatch auto 跳过写了警告描述" "$(grep -c "APatch：默认不加载" "$A/module.prop")" "1"
chk "APatch auto 跳过 apply_result=skipped" "$(cat "$A/state/apply_result" 2>/dev/null)" "skipped"

A="$TMP/a3"; build_apply "$A"
rc=$(run_apply "$A" 1 0 0 0 0); chk "APatch 未放行手动 apply 被拒（rc=1）" "$rc" "1"
chk "APatch 手动被拒 apply_result=skipped" "$(cat "$A/state/apply_result" 2>/dev/null)" "skipped"

A="$TMP/a4"; build_apply "$A"
rc=$(run_apply "$A" 0 0 0 0 1); chk "正常 auto apply 继续（不被门禁误拦）" "$rc" "1"

rm -rf "$TMP"
exit "$fail"
