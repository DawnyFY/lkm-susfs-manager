#!/bin/sh
# 离线测试：service.sh 启动入口（Magisk 补位；KernelSU / APatch 跳过）
set -u
REPO="$1"
TMP=$(mktemp -d)
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 expect=[$3] got=[$2]"; fail=1; fi; }

MOD="$TMP/mod"
mkdir -p "$MOD/state"
# service.sh 里模块路径是写死的，测试时替换成临时目录
sed "s#/data/adb/modules/susfs_allinone#$MOD#g" "$REPO/service.sh" > "$MOD/service.sh"

# 替身只实现 service.sh 依赖的函数（heredoc 加引号，避免测试期展开变量）
cat > "$MOD/common.sh" <<'EOF'
boot_gate_ok() { [ "${FAKE_BOOT:-1}" = "1" ]; }
_cf_gate() { [ "${FAKE_CF:-1}" = "1" ]; }
root_family() { printf "%s" "${FAKE_RF:-Magisk}"; }
cfg_ensure() { :; }
cfg_load() { auto_load=${FAKE_AUTOLOAD:-1}; }
clear_boot_guard() { echo cleared > "__MOD__/state/.cleared"; }
EOF

cat > "$MOD/apply.sh" <<'EOF'
#!/system/bin/sh
echo "AUTOLOAD=${AUTOLOAD:-0}" > "__MOD__/state/.applied"
exit ${FAKE_RC:-0}
EOF

sed -i "s#__MOD__#$MOD#g" "$MOD/common.sh" "$MOD/apply.sh"

run() {
    rm -f "$MOD/state/.applied" "$MOD/state/.cleared"
    env FAKE_RF="$1" FAKE_AUTOLOAD="$2" FAKE_CF="$3" FAKE_RC="$4" FAKE_BOOT="$5" \
        sh "$MOD/service.sh" >/dev/null 2>&1
    echo $?
}
applied() { [ -f "$MOD/state/.applied" ] && echo yes || echo no; }
cleared() { [ -f "$MOD/state/.cleared" ] && echo yes || echo no; }

# 1. KernelSU / APatch 已有 boot-completed，service 直接退出
chk "KernelSU 跳过" "$(run KernelSU 1 1 0 1)" "0"
chk "KernelSU 未调用 apply" "$(applied)" "no"
chk "APatch 跳过" "$(run APatch 1 1 0 1)" "0"
chk "APatch 未调用 apply" "$(applied)" "no"

# 2. Magisk：应用规则并清守卫标记
chk "Magisk 返回 0" "$(run Magisk 1 1 0 1)" "0"
chk "Magisk 调用 apply" "$(applied)" "yes"
chk "apply 带 AUTOLOAD=1" "$(cat "$MOD/state/.applied" 2>/dev/null)" "AUTOLOAD=1"
chk "成功后清守卫" "$(cleared)" "yes"

# 3. 关闭自动加载：不应用、不清守卫
chk "auto_load=0 返回 0" "$(run Magisk 0 1 0 1)" "0"
chk "auto_load=0 不 apply" "$(applied)" "no"
chk "auto_load=0 不清守卫" "$(cleared)" "no"

# 4. 文件被改：拒绝应用
chk "校验失败返回 0" "$(run Magisk 1 0 0 1)" "0"
chk "校验失败不 apply" "$(applied)" "no"

# 5. apply 失败：保留守卫标记，下次开机暂停自动加载
chk "apply 失败返回非 0" "$(run Magisk 1 1 1 1)" "1"
chk "失败时不清守卫" "$(cleared)" "no"

# 6. 模块被禁用/安全模式
chk "门禁不通时提前退出" "$(run Magisk 1 1 0 0)" "0"
chk "门禁不通不 apply" "$(applied)" "no"

rm -rf "$TMP"
exit "$fail"
