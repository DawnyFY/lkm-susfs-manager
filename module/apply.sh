#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# 应用 SUSFS 规则：确保 LKM 已加载，设置 sdcard 根路径，再写 sus_path / hide_modules 等。
MODDIR=/data/adb/modules/susfs_allinone
. "$MODDIR/common.sh"
LOG=$MODDIR/apply.log
mkdir -p "$STATE" 2>/dev/null

# 日志过大时只保留最近 500 行
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG" 2>/dev/null)" -gt 262144 ]; then
    tail -n 500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
fi
exec >>"$LOG" 2>&1
echo ""
echo "=== apply $(now_stamp) ==="
echo "[i] root: $(root_family)"

set_description() {
    prop="$MODDIR/module.prop"
    [ -f "$prop" ] || return 0
    _tmp="$prop.tmp"
    # 用 awk 写入，避免描述里的 # & 等字符破坏 sed 表达式
    awk -v d="$1" '
        /^description=/ { print "description=" d; next }
        { print }
    ' "$prop" > "$_tmp" 2>/dev/null && mv -f "$_tmp" "$prop" 2>/dev/null
}

# apply_result: success / partial / skipped / failed（仅表示脚本执行结果，不等同于功能生效）
_set_apply_result() {
    mkdir -p "$STATE" 2>/dev/null
    printf '%s\n' "$1" > "$STATE/apply_result" 2>/dev/null
    printf '%s\n' "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)" > "$STATE/apply_result_boot" 2>/dev/null
}

[ -f "$MODDIR/disable" ] && { echo "模块已禁用"; _set_apply_result skipped; exit 0; }
[ -f "$MODDIR/remove" ] && { echo "模块待移除"; _set_apply_result skipped; exit 0; }
if [ -f "$STATE/loading" ]; then
    # 残留超过 10 分钟视为上次异常退出，自动清理后继续，避免永久跳过
    if file_older_than "$STATE/loading" 600 || susfs_kernel_ready; then
        rm -f "$STATE/loading"
        echo "[!] 清理 state/loading 残留（>10 分钟或 LKM 已就绪）"
    else
        echo "[!] 上次 LKM 加载未完成（state/loading 残留），跳过规则应用（稍后会重试）"
        _set_apply_result skipped
        # 返回 3(跳过)：调用方不能把"没执行"当成成功而清掉启动守卫
        exit 3
    fi
fi

# 互斥：开机脚本与 WebUI 可能同时触发 apply，重复执行会让 our_paths 清单错乱
_lk_ok=0
lock_acquire "$STATE/apply.lock" 180 && _lk_ok=1
if [ "$_lk_ok" = "0" ]; then
    # 常见情形：开机自动 apply 还在跑，用户又点了「保存并应用」。
    # 直接跳过会让用户以为按钮没反应，先等一会儿（最多 10 秒）。
    echo "[i] 另一个 apply 正在运行，等待其结束（最多 10 秒）"
    _lk_wait=0
    while [ "$_lk_wait" -lt 20 ]; do
        sleep 0.5 2>/dev/null || sleep 1
        if lock_acquire "$STATE/apply.lock" 180; then _lk_ok=1; break; fi
        _lk_wait=$((_lk_wait + 1))
    done
fi
if [ "$_lk_ok" = "0" ]; then
    _lk_info=""
    read -r _lk_info < "$STATE/apply.lock/pid" 2>/dev/null
    echo "[!] 另一个 apply 正在运行（持有者: ${_lk_info:-未知}），跳过本次"
    echo "[i] 若持续出现，说明上次 apply 被中断；锁会在 3 分钟后自动失效，或重启后立即释放"
    # 不覆盖已有 apply_result，避免并发时状态在 success/skipped 之间闪变
    # 返回非 0：调用方（boot-completed）不能把"没执行"当成成功
    exit 1
fi
trap 'lock_release "$STATE/apply.lock"' EXIT

restore_config_if_missing
ensure_skip_hide_file
cfg_ensure
cfg_load
# 配置不能改变这些路径：否则可借 MODDIR/STATE 加载任意脚本或写入任意位置
MODDIR=/data/adb/modules/susfs_allinone
CONFIG=$MODDIR/config
STATE=$MODDIR/state
hide_sus_mnts=${hide_sus_mnts:-1}
avc_spoof=${avc_spoof:-0}
replace_rules=${replace_rules:-0}
hide_compat_matrix=${hide_compat_matrix:-0}
hide_revanced=${hide_revanced:-0}
hide_custom_rom=${hide_custom_rom:-0}
hide_ksu_loop=${hide_ksu_loop:-0}
fake_cmdline=${fake_cmdline:-0}
fake_cmdline_value=${fake_cmdline_value:-}
force_kmi=${force_kmi:-}
hide_gapps=${hide_gapps:-0}
hide_dex2oat=${hide_dex2oat:-0}
hide_scene=${hide_scene:-0}
auto_try_umount=${auto_try_umount:-0}
skip_detection_paths=${skip_detection_paths:-1}
skip_legit_mounts=${skip_legit_mounts:-1}
hide_vendor_sepolicy=${hide_vendor_sepolicy:-0}
vold_isolation=${vold_isolation:-0}

# 完整性校验先做：后面的早退不能绕过它
_cf_run 2>&1 || { echo "[!] 文件被修改，拒绝应用规则"; _set_apply_result failed; exit 1; }

# 自动路径：已处于暂停状态时直接跳过（保留守卫/暂停标记，避免被调用方误清）
if [ "${AUTOLOAD:-0}" = "1" ] && [ -f "$STATE/autoload_paused" ] && ! susfs_kernel_ready; then
    echo "[!] 自动加载已暂停，跳过本次应用（ctl.sh resume_autoload 恢复）"
    set_description "⚠️ 自动加载已暂停（ctl.sh resume_autoload 恢复）"
    _set_apply_result skipped
    exit 3
fi

# APatch/KernelPatch 共存安全模式：
# kpimg 已 hook SELinux 审计面（avc_denied/slow_avc_audit/selinux_hide），
# avc_spoof 与它语义重叠，检测到 KernelPatch 时强制关闭。
if kernelpatch_present; then
    echo apatch > "$STATE/coexist_mode" 2>/dev/null
    if [ "$avc_spoof" = "1" ] && coexist_disable_avc_spoof; then
        echo "[!] 检测到 APatch/KernelPatch 内核：avc_spoof 与 kpimg 的 SELinux hook 重叠，本次强制关闭"
        avc_spoof=0
    fi
else
    rm -f "$STATE/coexist_mode" 2>/dev/null
fi

# 崩溃防护：上次启动 pstore 里出现本模块相关 panic/oops → 自动暂停本次开机应用
if pstore_crash_suspect; then
    if [ "${AUTOLOAD:-0}" = "1" ]; then
        pause_autoload
        echo "[!] 检测到上次启动疑似本模块崩溃（pstore 含 panic/oops 与 susfs 栈），已暂停自动加载"
        echo "[i] 确认内核稳定后执行 ctl.sh resume_autoload（会记下已确认记录）"
        set_description "❌ 上次启动疑似 SUSFS 崩溃，已暂停自动加载（ctl.sh resume_autoload）"
        _set_apply_result skipped
        # 返回 3(跳过)：调用方不能把"没执行"当成成功而清掉守卫/暂停标记
        exit 3
    else
        echo "[!] 警告：pstore 显示上次疑似本模块崩溃，仍按手动请求继续"
    fi
fi

# APatch/KernelPatch 共存防护：默认不外挂 SUSFS LKM（自动跳过、手动拒绝，需显式放行）
if ! susfs_kernel_ready && kernelpatch_present && ! apatch_lkm_allowed; then
    if [ "${AUTOLOAD:-0}" = "1" ]; then
        echo "[!] APatch/KernelPatch 内核：默认不自动加载 SUSFS LKM（与 kpimg 共存有崩溃风险）"
        echo "[i] 内核已内置 SUSFS 则无需外挂；确实要试外挂，先执行 ctl.sh allow_lkm"
        set_description "⚠️ APatch：默认不加载 SUSFS LKM（共存风险）；内置 SUSFS 或 ctl.sh allow_lkm"
        _set_apply_result skipped
        exit 0
    fi
    echo "[!] APatch/KernelPatch 内核：未放行外挂 LKM，手动操作已拒绝（先执行 ctl.sh allow_lkm）"
    set_description "⚠️ APatch：手动外挂需先 ctl.sh allow_lkm"
    _set_apply_result skipped
    exit 1
fi

# 只允许 KMI 名称字符，防止路径穿越
case "$force_kmi" in *[!A-Za-z0-9._-]*) force_kmi="" ;; esac
spoof_uname=${spoof_uname:-0}
spoof_uname_release=${spoof_uname_release:-}
spoof_uname_version=${spoof_uname_version:-}


# 早期版本曾在 /data/local/tmp 建探测目录；这里只提示，不删除模块目录以外的路径
for _j in /data/local/tmp/.susfs_probe_dir /data/local/tmp/.susfs_cap_probe /data/local/tmp/.diag_probe; do
    [ -e "$_j" ] && echo "[i] 发现旧版遗留目录，可手动删除：$_j"
done

_rule_fails=0
_rule_missing=0

# 1. 确保内核侧 SUSFS：LKM 已加载，或内核已内置（内置时无需也无法再加载）
if ! susfs_kernel_ready; then
    if [ "$AUTOLOAD" = "1" ]; then
        # 上次自动加载后没能完成启动（marker 还在），本次暂停
        if autoload_paused || [ -f "$(boot_guard_path)" ]; then
            pause_autoload
            echo "[!] 上次加载后未能完成启动，本次暂停自动加载"
            echo "[i] 请先确认 KMI 选对：WebUI 配置页的「强制指定 KMI」，或执行 ctl.sh kmiinfo 查看"
            echo "[i] 确认后点「加载并应用」（手动路径不受暂停限制），或执行 ctl.sh resume_autoload"
            set_description "⚠️ 自动加载已暂停（上次启动未完成），请检查 KMI 后手动加载"
            exit 1
        fi
    fi
    echo "[i] 内核侧未发现 SUSFS（LKM 未加载且无内置接口），先加载 LKM"
    if [ "$AUTOLOAD" = "1" ]; then
        # 自动路径：先落守卫标记，加载后若没能完成启动，下次会自动暂停
        mark_boot_guard "$(cat /proc/sys/kernel/osrelease 2>/dev/null)"
        sh "$MODDIR/load.sh" auto
    else
        sh "$MODDIR/load.sh" manual
    fi
    rc=$?
    if [ "$rc" = "2" ]; then
        # load.sh 已判定"未匹配内核"并写好模块描述，不要覆盖成"LKM 加载失败"
        echo "[!] 未匹配内核/KMI，规则未应用（模块描述已更新）"
        _set_apply_result failed
        exit 1
    fi
    if [ "$rc" != "0" ]; then
        echo "[!] 加载失败，无法应用规则"
        set_description "❌ $(susfs_hint insmod)"
        _set_apply_result failed
        exit 1
    fi
    # 子进程加载成功后，本进程的探测缓存必须失效，否则后续 select 会走旧分支
    _SUSFS_KIND=""
fi

# 内置 SUSFS 的 KSU 依赖提示：上游 susfs4ksu 补丁基于 KernelSU 内核树，内置但未启用 CONFIG_KSU
# 意味着 uid/挂载判定可能走退化路径（本 LKM 移植版是可选的），非阻塞，只记录。
if [ "$(susfs_kernel_kind)" = "builtin" ]; then
    _KCFG_KSU=$(kernel_config_get CONFIG_KSU)
    if [ "$_KCFG_KSU" = "n" ]; then
        echo "[!] 内核内置 SUSFS 但 CONFIG_KSU 明确未启用：uid/挂载判定可能退化；若规则异常请记录该内核配置"
    fi
fi

# 2. 选择可用的 ksu_susfs：优先当前管理器/分支自带，失败回退模块备份
NODE_ONLY=0
if BIN=$(select_susfs_bin); then
    echo "[i] ksu_susfs: $BIN"
elif susfs_node_ready; then
    # 第三级回退：没有可用的 ksu_susfs，但内核节点还在 → 直接写节点下发规则
    echo "[!] 未找到可用的 ksu_susfs，改用 /proc/susfs_* 节点直接下发"
    echo "[i] 节点后端支持：sus_path / hide_mounts / sus_map / hide_modules；"
    echo "    不支持：sus_path_loop / uname 伪装 / try_umount（这些需要 ioctl，节点没有接口）"
    NODE_ONLY=1
    BIN=""
else
    echo "[!] 缺少 ksu_susfs"
    set_description "❌ $(susfs_hint missing)"
    _set_apply_result failed
    exit 1
fi
VARIANT=""
[ "$NODE_ONLY" = "1" ] || VARIANT=$("$BIN" show variant 2>/dev/null)
if [ -z "$VARIANT" ] && ! susfs_bin_runnable "$BIN"; then
    echo "[!] 当前 ksu_susfs 无法执行（可能是架构不符或文件损坏）: $BIN"
    echo "[i] 建议重装管理器，或让模块改用内置备份（apply 会自动回退）"
fi
if [ -z "$VARIANT" ] && [ -x "$MODDIR/bin/ksu_susfs_good" ] && [ "$BIN" != "$MODDIR/bin/ksu_susfs_good" ]; then
    echo "[i] 当前 ksu_susfs 无法通信，切换到模块备份"
    BIN="$MODDIR/bin/ksu_susfs_good"
    VARIANT=$("$BIN" show variant 2>/dev/null)
fi
if [ "$NODE_ONLY" != "1" ]; then
    [ -n "$VARIANT" ] || { echo "[!] ksu_susfs 无法与内核通信"; set_description "❌ $(susfs_hint comm)"; _set_apply_result failed; exit 1; }
fi
# 回退到模块备份二进制时，它可能比 LKM 旧：缺 avc_log_spoofing / set_sdcard_root_path /
# try_umount 等新命令，现象很像「内核不支持」。这里把真实原因说出来，避免误判。
USING_BACKUP_BIN=0
case "$BIN" in */ksu_susfs_good) USING_BACKUP_BIN=1 ;; esac
if [ "$USING_BACKUP_BIN" = "1" ]; then
    echo "[!] 正在使用模块备份的 ksu_susfs（管理器自带的无法通信）"
    echo "[i] 备份二进制可能较旧：下面若出现「不支持 / 设置失败」，先重装模块或更新管理器，再判断是否内核问题"
fi
VERSION=$("$BIN" show version 2>/dev/null)
FEATURES=$("$BIN" show enabled_features 2>/dev/null)
has_feature() { printf "%s\n" "$FEATURES" | grep -qx "$1"; }
# 用真实内核选 KMI：osrelease 可能被本模块的 uname 伪装改写
REL=$(real_kernel_release 2>/dev/null)
[ -n "$REL" ] || REL=$(cat /proc/sys/kernel/osrelease 2>/dev/null)
. "$MODDIR/kmi.sh"
KMI=$(select_kmi "$REL" "$MODDIR" 2>/dev/null)
[ -n "$force_kmi" ] && [ -s "$MODDIR/lib/susfs_guard_lkm-$force_kmi.ko" ] && KMI="$force_kmi"
KMI=${KMI:-unknown}

# 3. sus_path 依赖 sdcard 根路径，先等待 /sdcard/Android/data
count=0
until [ -d /sdcard/Android/data ] || [ "$count" -ge 15 ]; do
    sleep 1
    count=$((count + 1))
done
if [ -d /sdcard/Android/data ]; then
    # 部分内核不支持这两个命令（需要 susfs v1.5.8+），按返回码如实记录
    _sd_rc=$("$BIN" set_sdcard_root_path /sdcard >/dev/null 2>&1; echo $?)
    _ad_rc=$("$BIN" set_android_data_root_path /sdcard/Android/data >/dev/null 2>&1; echo $?)
    if [ "$_sd_rc" = "0" ] && [ "$_ad_rc" = "0" ]; then
        echo "[i] sdcard 根路径已设置"
    else
        if [ "${USING_BACKUP_BIN:-0}" = "1" ]; then
            echo "[i] sdcard 根路径设置失败：当前用的是模块备份的旧 ksu_susfs，缺该命令（需 susfs v1.5.8+ 的二进制）；不是内核问题"
        else
            echo "[i] 内核不支持 sdcard 根路径设置（需 susfs v1.5.8+），跳过"
        fi
    fi
else
    echo "[!] /sdcard/Android/data 15 秒内未出现，sus_path 可能不生效"
fi

# 4. 特性开关
# 部分 LKM 不在 enabled_features 里上报这两项，但 /proc 节点与超调用是存在的，
# 所以判定用「特性位 or /proc 节点」，避免默认开启的项被静默跳过。
# 部分 LKM 不在 enabled_features 里上报这两项，但 /proc 节点与超调用可用；
# 判定用「特性位 or /proc 节点」，失败则本次开机内标记不可用，避免每轮刷同一错误。
if [ "$hide_sus_mnts" = "1" ]; then
    if has_feature CONFIG_KSU_SUSFS_HIDE_SUS_MNTS || [ -e /proc/susfs_hide_mounts ]; then
        if [ -f "$STATE/hide_sus_unsupported" ]; then
            echo "[i] hide_sus_mnts 已标记不可用，跳过（重新加载 LKM 后会自动重试）"
        elif "$BIN" hide_sus_mnts_for_non_su_procs 1 >/dev/null 2>&1; then
            echo "[i] hide_sus_mnts_for_non_su_procs=1"
        else
            echo "[!] hide_sus_mnts 设置失败，本次开机内不再重试"
            : > "$STATE/hide_sus_unsupported" 2>/dev/null
        fi
    else
        echo "[i] 内核未提供 hide_sus_mnts 接口（无特性位、无 /proc/susfs_hide_mounts），跳过"
    fi
fi
# AVC 日志伪装的三条路径，按可用性依次尝试：
#   1) ksu_susfs enable_avc_log_spoofing（新版 CLI 才有）
#   2) LKM 参数 /sys/module/susfs_guard_lkm/parameters/avc_su_ctx
#      （官方 KernelSU 常见：功能在 LKM 里，但 CLI 没有对应命令）
#   3) 都没有 → 标记不可用，本次开机不再重试
AVC_PARAM=/sys/module/susfs_guard_lkm/parameters/avc_su_ctx
AVC_REAL_CTX="u:r:ksu:s0"
AVC_SPOOF_CTX="u:r:priv_app:s0:c512,c768"
if has_feature CONFIG_KSU_SUSFS_AVC_LOG_SPOOFING || [ -e /proc/susfs_avc_spoof ] || [ -e "$AVC_PARAM" ]; then
    if [ "$avc_spoof" = "1" ]; then
        if "$BIN" enable_avc_log_spoofing 1 >/dev/null 2>&1; then
            echo "[i] avc_log_spoofing=1（ksu_susfs 命令）"
        elif [ -w "$AVC_PARAM" ]; then
            _avc_cur=$(cat "$AVC_PARAM" 2>/dev/null)
            if [ "$_avc_cur" = "$AVC_SPOOF_CTX" ]; then
                echo "[i] avc_log_spoofing=1（LKM 参数已生效：$_avc_cur）"
            elif printf '%s\n' "$AVC_SPOOF_CTX" > "$AVC_PARAM" 2>/dev/null; then
                # 记下开启前的原值，关闭时按原值还原（audit M1）：
                # 硬编码 u:r:ksu:s0 会覆盖用户自定义的 su 域（Magisk/自定义 su 设备上这个硬编码值本身就是错的）
                if [ ! -s "$STATE/avc_orig_ctx" ] && [ -n "$_avc_cur" ]; then
                    printf '%s\n' "$_avc_cur" > "$STATE/avc_orig_ctx" 2>/dev/null
                fi
                _avc_now=$(cat "$AVC_PARAM" 2>/dev/null)
                if [ "$_avc_now" = "$AVC_SPOOF_CTX" ]; then
                    echo "[i] avc_log_spoofing=1（经 LKM 参数：$_avc_cur → $_avc_now）"
                else
                    echo "[!] avc_log_spoofing 写入参数后未生效（读回：$_avc_now）"
                fi
            else
                echo "[!] avc_log_spoofing 无法开启：CLI 无该命令，参数写入被拒绝"
                : > "$STATE/avc_unsupported" 2>/dev/null
            fi
        elif susfs_avc_node_set 1; then
            echo "[i] avc_log_spoofing=1（经 /proc/susfs_avc_spoof 节点）"
        else
            echo "[!] avc_log_spoofing 不可用：CLI 无该命令，LKM 未暴露 avc_su_ctx，节点也不可用"
            : > "$STATE/avc_unsupported" 2>/dev/null
        fi
    else
        "$BIN" enable_avc_log_spoofing 0 >/dev/null 2>&1
        # 参数通道打开的，关闭时要还原，否则 AVC 日志会继续被改写
        if [ -w "$AVC_PARAM" ]; then
            _avc_cur=$(cat "$AVC_PARAM" 2>/dev/null)
            # 只有"当前确实是伪装值"才需要还原（audit R2-1）：
            # 记录可能来自 1.2.9 的 avc_spoof.sh、或 LKM 重载后早已过期，
            # 无条件信任会造成「配置关、伪装反而被打开」。
            if [ "$_avc_cur" = "$AVC_SPOOF_CTX" ]; then
                _avc_target=$AVC_REAL_CTX
                if [ -s "$STATE/avc_orig_ctx" ]; then
                    _avc_saved=$(cat "$STATE/avc_orig_ctx" 2>/dev/null)
                    case "$_avc_saved" in
                        ''|"$AVC_SPOOF_CTX") ;;   # 空 / 记录本身是伪装值 → 不可信，用默认
                        *) _avc_target=$_avc_saved ;;
                    esac
                fi
                if printf '%s\n' "$_avc_target" > "$AVC_PARAM" 2>/dev/null; then
                    echo "[i] avc_log_spoofing=0（参数已还原：$_avc_cur → $_avc_target）"
                fi
            else
                echo "[i] avc_log_spoofing=0（当前值不是伪装值，无需还原）"
            fi
            rm -f "$STATE/avc_orig_ctx" 2>/dev/null
        fi
    fi
else
    echo "[i] 内核未提供 avc_log_spoofing 接口（LKM 无该特性，也无 avc_su_ctx 参数），跳过"
fi
# 读取配置文件的第一个字段，忽略注释和空行
# 清洗单行：去 \r、去注释、去首尾空白

# 被守卫跳过的路径：如果内核里还留着旧规则，撤掉它，避免升级后仍然出现同样的问题
_skip_revert() {
    _sr_p=$1
    [ -n "$_sr_p" ] || return 0
    grep -F -q "path=$_sr_p " /proc/susfs_path 2>/dev/null || return 0
    if susfs_path_del "$_sr_p" 2>/dev/null; then
        unrecord_our_path "$_sr_p" 2>/dev/null
        echo "[i]   已撤销内核中的旧规则：$_sr_p"
    fi
    return 0
}

# 历史遗留清理（与当前开关无关）：我们以前可能把 App 安装目录记进过自己的规则账本
# （1.3.0 之前的 hide_gapps 就会这么干）。这类规则必然造成「安装记录与 APK 不符」，
# 关掉开关也不会自动消失（replace_rules=0 是只追加），所以每次 apply 都主动撤销一遍。
_prune_ledger_dirs() {
    _pl_f=$(our_paths_file)
    [ -s "$_pl_f" ] || return 0
    _pl_tmp="$_pl_f.prune.$$"
    _pl_n=0
    : > "$_pl_tmp" 2>/dev/null
    while IFS= read -r _pl_p || [ -n "$_pl_p" ]; do
        [ -n "$_pl_p" ] || continue
        if is_app_install_dir "$_pl_p" && susfs_path_del "$_pl_p"; then
            echo "[i] 已撤销历史遗留的安装目录规则：$_pl_p"
            _pl_n=$((_pl_n + 1))
            continue
        fi
        printf '%s\n' "$_pl_p" >> "$_pl_tmp" 2>/dev/null
    done < "$_pl_f"
    mv -f "$_pl_tmp" "$_pl_f" 2>/dev/null
    return 0
}
_prune_ledger_dirs

# 5. sus_path
# replace_rules=1：只移除本模块上次写入的规则（不影响其他隐藏模块）
# replace_rules=2：整表清空（显式高危，会连同其他模块的规则一起清掉）
case "$replace_rules" in
    1)
        # hide_mounts / sus_map 的归属清单与 sus_path 无关，必须无条件撤销
        clear_own_hide_mounts
        clear_own_sus_map
        if [ -s "$(our_paths_file)" ]; then
            clear_own_paths
        else
            clear_migrated_paths "$CONFIG/sus_path.txt"
        fi
        ;;
    2) if clear_all_paths; then echo "[!] 已清空全部 sus_path 规则（replace_rules=2）"; else echo "[!] 清空 sus_path 失败（内核拒绝）"; _rule_fails=$((_rule_fails + 1)); fi ;;
esac
# 路径表被清理后，loop 账本也必须失效，否则本次 apply 不会重新注册
if [ "$replace_rules" = "1" ] || [ "$replace_rules" = "2" ]; then
    rm -f "$STATE/sus_path_loop_added" "$STATE/sus_path_loop_added.boot" 2>/dev/null
fi
if [ -f "$CONFIG/sus_path.txt" ]; then
    while IFS= read -r _line || [ -n "$_line" ]; do
        path=$(clean_entry "$_line")
        [ -n "$path" ] || continue
        case "$path" in
            /*) ;;
            *) echo "[!] 忽略非绝对路径: $path"; continue ;;
        esac
        # 检测类应用自身的数据目录默认不隐藏（隐藏它们会让检测工具判定异常）
        if [ "${skip_detection_paths:-1}" = "1" ] && is_detection_app_path "$path"; then
            echo "[i] 跳过检测类应用数据目录: $path"
            continue
        fi
        # 陈旧 inode 检测：目录被删除重建后，/proc/susfs_path 里那行还在但 dev/ino 已失效。
        # 只判「行是否存在」会让它永远显示「已存在」、永不重加（loop 规则早已按 dev/ino 判，
        # 普通规则此前没有，这里补齐）。路径当前不存在时保留旧规则，交给 sus_path_loop 处理。
        _sp_line=$(grep -F "path=$path " /proc/susfs_path 2>/dev/null | head -n 1)
        _sp_present=0
        if [ -n "$_sp_line" ]; then
            _sp_present=1
            case "$_sp_line" in
                *pending*) : ;;
                *dev=*ino=*)
                    if [ -e "$path" ]; then
                        _sp_ino=$(stat -c %i "$path" 2>/dev/null)
                        # 只比 ino：SUSFS 输出的 dev 是 major<<20|minor，与 stat -c %d 的原始
                        # st_dev 编码不同，比 dev 会永远不相等、导致每次 apply 撤旧重加
                        case "$_sp_line" in
                            *" ino=$_sp_ino "*) ;;
                            *)
                                if susfs_path_del "$path"; then
                                    _sp_present=0
                                    echo "[i] sus_path $path (inode 已变，撤销旧规则后重加)"
                                else
                                    echo "[!] sus_path $path (inode 已变，但旧规则无法撤销)"
                                    _rule_fails=$((_rule_fails + 1))
                                fi
                                ;;
                        esac
                    fi
                    ;;
                *) : ;;  # 老版本不报 dev/ino，无从判断，维持原行为
            esac
        fi
        case "$path" in
            *[[:space:]]*)
                echo "[i] sus_path $path (路径含空白，内核协议以空格分隔，无法下发；请改名或改用 sus_path_loop)"
                continue
                ;;
        esac
        if is_ephemeral_path "$path"; then
            echo "[i] sus_path $path (虚拟/临时路径，内核不接受；建议从 sus_path 移除)"
            continue
        fi
        if is_app_install_dir "$path"; then
            echo "[i] sus_path $path (系统 App 安装目录，隐藏会造成「安装记录与 APK 不符」，跳过)"
            _skip_revert "$path"
            continue
        fi
        if [ "$_sp_present" = "1" ]; then
            echo "[=] sus_path $path (已存在)"
        elif [ ! -e "$path" ]; then
            # 路径不存在：内核必然拒绝，但这属于「用户配置里的失效条目」，
            # 不该计入规则失败 —— 服务器日志里有用户因此累积到 70 条失败，
            # 真正需要看到的是「这些路径不存在」这一条信息（audit 现场：游戏反作弊临时文件）
            echo "[i] sus_path $path (路径不存在，跳过；临时路径请改用 sus_path_loop.txt)"
            _rule_missing=$((_rule_missing + 1))
        elif susfs_path_add "$path"; then
            record_our_path "$path"
            echo "[+] sus_path $path"
        else
            echo "[=] sus_path $path (失败)"
            _rule_fails=$((_rule_fails + 1))
        fi
    done < "$CONFIG/sus_path.txt"
fi

# 5a. sus_path_loop：延迟解析规则，不在用户态跑常驻循环。
# 内核会保存路径并重试解析（有界），路径出现后自动隐藏。
# 账本只用于去重；每次 apply 都回读 /proc/susfs_path，失效/pending 已过期时重新 add。
if [ -f "$CONFIG/sus_path_loop.txt" ]; then
    _spl_boot=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
    [ -n "$_spl_boot" ] || _spl_boot="btime_$(awk '/^btime /{print $2}' /proc/stat 2>/dev/null)"
    _spl_ledger="$STATE/sus_path_loop_added"
    _spl_bootf="$STATE/sus_path_loop_added.boot"
    if [ "$(cat "$_spl_bootf" 2>/dev/null)" != "$_spl_boot" ]; then
        : > "$_spl_ledger" 2>/dev/null
        printf '%s\n' "$_spl_boot" > "$_spl_bootf" 2>/dev/null
    fi
    _spl_cfg_tmp="$STATE/sus_path_loop.current"
    : > "$_spl_cfg_tmp" 2>/dev/null
    while IFS= read -r _line || [ -n "$_line" ]; do
        path=$(clean_entry "$_line")
        [ -n "$path" ] || continue
        case "$path" in
            /*) ;;
            *) echo "[!] 忽略非绝对路径: $path"; continue ;;
        esac
        if [ "${skip_detection_paths:-1}" = "1" ] && is_detection_app_path "$path"; then
            echo "[i] 跳过检测类应用数据目录: $path"
            continue
        fi
        printf '%s\n' "$path" >> "$_spl_cfg_tmp" 2>/dev/null
        _spl_line=$(grep -F "path=$path " /proc/susfs_path 2>/dev/null | head -n 1)
        _spl_should_add=1
        _spl_state=missing
        if [ -n "$_spl_line" ]; then
            case "$_spl_line" in
                *pending*) _spl_state=pending ;;
                *) _spl_state=active ;;
            esac
            if [ "$_spl_state" = "pending" ]; then
                if [ -e "$path" ]; then
                    _spl_should_add=1
                else
                    _spl_should_add=0
                fi
            elif [ -e "$path" ]; then
                _spl_ino=$(stat -c %i "$path" 2>/dev/null)
                case "$_spl_line" in
                    *" ino=$_spl_ino "*) _spl_should_add=0 ;;
                esac
            else
                _spl_should_add=0
            fi
        fi
        if [ "$_spl_should_add" = "0" ]; then
            grep -Fqx -- "$path" "$_spl_ledger" 2>/dev/null || printf '%s\n' "$path" >> "$_spl_ledger" 2>/dev/null
            record_our_path "$path"
            case "$_spl_state" in
                pending) echo "[~] sus_path_loop $path (已注册，等待路径出现)" ;;
                active) echo "[=] sus_path_loop $path (已生效)" ;;
                *) echo "[=] sus_path_loop $path (已注册)" ;;
            esac
            continue
        fi
        # 账本命中但规则已失效：先移除旧账本行，再重新 add
        if grep -Fqx -- "$path" "$_spl_ledger" 2>/dev/null; then
            _spl_tmp="$_spl_ledger.tmp.$$"
            grep -Fvx -- "$path" "$_spl_ledger" > "$_spl_tmp" 2>/dev/null
            mv -f "$_spl_tmp" "$_spl_ledger" 2>/dev/null
        fi
        if "$BIN" add_sus_path_loop "$path" >/dev/null 2>&1; then
            _spl_after=$(grep -F "path=$path " /proc/susfs_path 2>/dev/null | head -n 1)
            if [ -z "$_spl_after" ]; then
                echo "[!] sus_path_loop $path 命令返回成功但内核未注册"
                _rule_fails=$((_rule_fails + 1))
                continue
            fi
            printf '%s\n' "$path" >> "$_spl_ledger" 2>/dev/null
            record_our_path "$path"
            case "$_spl_after" in
                *pending*) echo "[~] sus_path_loop $path (已注册，等待路径出现)" ;;
                *) echo "[+] sus_path_loop $path" ;;
            esac
        else
            # 节点后端（或 CLI 不支持 loop）时：路径已存在就退化成普通 sus_path，
            # 有限退让，不是常驻循环 —— 至少不会让整条规则白配
            if [ "$NODE_ONLY" = "1" ] && [ -e "$path" ] && susfs_path_add "$path"; then
                echo "[i] sus_path_loop $path（节点后端无 loop 接口，已按普通 sus_path 下发）"
            else
                echo "[!] sus_path_loop $path 失败（内核/ksu_susfs 可能不支持 add_sus_path_loop）"
                _rule_fails=$((_rule_fails + 1))
            fi
        fi
    done < "$CONFIG/sus_path_loop.txt"
    # 配置里删掉的 loop 行：用 /proc 的 del 逐条撤销，不能等重启
    if [ -s "$_spl_ledger" ]; then
        while IFS= read -r _spl_old || [ -n "$_spl_old" ]; do
            [ -n "$_spl_old" ] || continue
            grep -Fqx -- "$_spl_old" "$_spl_cfg_tmp" 2>/dev/null && continue
            if susfs_path_del "$_spl_old"; then
                unrecord_our_path "$_spl_old"
                _spl_tmp="$_spl_ledger.tmp.$$"
                grep -Fvx -- "$_spl_old" "$_spl_ledger" > "$_spl_tmp" 2>/dev/null
                mv -f "$_spl_tmp" "$_spl_ledger" 2>/dev/null
                echo "[i] sus_path_loop $_spl_old (已移除)"
            else
                echo "[!] sus_path_loop $_spl_old 无法逐条删除（需重启或 replace_rules=2）"
                _rule_fails=$((_rule_fails + 1))
            fi
        done < "$_spl_ledger"
    fi
    rm -f "$_spl_cfg_tmp" 2>/dev/null
fi

# 5b. 扩展隐藏开关（只隐藏实际存在的路径，默认全关）
add_sus_path_safe() {
    _p=$1
    [ -n "$_p" ] || return 0
    if is_ephemeral_path "$_p"; then
        echo "[i] sus_path $_p (虚拟/临时路径，跳过)"
        return 0
    fi
    if is_app_install_dir "$_p"; then
        echo "[i] sus_path $_p (系统 App 安装目录，隐藏会造成「安装记录与 APK 不符」，跳过)"
        _skip_revert "$_p"
        return 0
    fi
    if grep -F -q "path=$_p " /proc/susfs_path 2>/dev/null; then
        echo "[=] sus_path $_p (已存在)"
    elif susfs_path_add "$_p"; then
        record_our_path "$_p"
        echo "[+] sus_path $_p"
    else
        echo "[=] sus_path $_p (失败)"
        _rule_fails=$((_rule_fails + 1))
    fi
}

if [ "$hide_compat_matrix" = "1" ]; then
    _n=0
    for _p in /system/etc/compat_matrix* /system_ext/etc/compat_matrix* /product/etc/compat_matrix* /vendor/etc/compat_matrix*; do
        [ -e "$_p" ] || continue
        _n=$((_n + 1))
        add_sus_path_safe "$_p"
    done
    [ "$_n" = "0" ] && echo "[i] 未发现 compat_matrix，跳过"
fi

if [ "$hide_revanced" = "1" ]; then
    _n=0
    for _d in /data/adb/modules/*revanced* /data/adb/modules/*youtube* /data/adb/modules/*microg* /data/adb/ksu/modules/*revanced* /data/adb/ksu/modules/*youtube*; do
        [ -d "$_d" ] || continue
        _n=$((_n + 1))
        add_sus_path_safe "$_d"
        [ -d "$_d/system" ] && add_sus_path_safe "$_d/system"
    done
    [ "$_n" = "0" ] && echo "[i] 未发现 revanced / youtube / microg 模块，跳过"
fi

if [ "$hide_custom_rom" = "1" ]; then
    _n=0
    for _p in /system/addon.d /system/etc/lineage /product/etc/lineage /system/etc/evolution /product/etc/evolution /system/etc/pixel /system/etc/derpfest /product/etc/derpfest; do
        [ -e "$_p" ] || continue
        _n=$((_n + 1))
        add_sus_path_safe "$_p"
    done
    [ "$_n" = "0" ] && echo "[i] 未发现自定义 ROM 痕迹，跳过（官方系统属正常）"
fi

if [ "$hide_ksu_loop" = "1" ]; then
    _loops=$(grep -E "^/dev/block/loop[0-9]+ /data/adb" /proc/mounts 2>/dev/null | cut -d" " -f2 | sort -u)
    if [ -z "$_loops" ]; then
        echo "[i] 未发现 /data/adb 下的 loop 挂载，跳过 KSU LOOP 隐藏"
    else
        while IFS= read -r _m; do
            [ -n "$_m" ] || continue
            add_sus_path_safe "$_m"
        done <<EOFL
$_loops
EOFL
    fi
fi

if [ "$fake_cmdline" = "1" ] && [ -n "$fake_cmdline_value" ]; then
    if has_feature CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG; then
        _cfl="$STATE/fake_cmdline.txt"
        mkdir -p "$STATE" 2>/dev/null
        printf "%s\n" "$fake_cmdline_value" > "$_cfl"
        if "$BIN" set_cmdline_or_bootconfig "$_cfl" >/dev/null 2>&1; then
            echo "[i] cmdline 伪装已生效: $fake_cmdline_value"
        else
            echo "[!] cmdline 伪装设置失败（内核已启用该特性，请查内核日志）"
            _rule_fails=$((_rule_fails + 1))
        fi
    else
        echo "[i] 内核未启用 SPOOF_CMDLINE_OR_BOOTCONFIG，跳过 cmdline 伪装"
    fi
fi

# 6. sus_mount
if [ -f "$CONFIG/sus_mount.txt" ]; then
    _sm_ok=0; _sm_bad=0
    while IFS= read -r _line || [ -n "$_line" ]; do
        path=$(clean_entry "$_line")
        [ -n "$path" ] || continue
        case "$path" in
            /*) ;;
            *) echo "[!] 忽略非绝对路径: $path"; continue ;;
        esac
        # 优先用上游现行接口（r18.5+ 的前缀表），旧 LKM 才回退 add_sus_mount
        if hide_mounts_has "$path"; then
            echo "[=] hide_mounts $path (已在表中，跳过)"
        elif hide_mounts_add "$path"; then
            _sm_ok=$((_sm_ok + 1))
            record_own_hide_mount "$path"
            echo "[+] hide_mounts $path"
        else
            sus_mount_add_once "$path"
            case $? in
                0) _sm_ok=$((_sm_ok + 1)); echo "[+] sus_mount $path" ;;
                2) echo "[=] sus_mount $path (本次开机已添加，跳过)" ;;
                *) _sm_bad=$((_sm_bad + 1)); echo "[=] sus_mount $path (失败)" ;;
            esac
        fi
    done < "$CONFIG/sus_mount.txt"
    _rule_fails=$((_rule_fails + _sm_bad))
    if [ "$_sm_ok" = "0" ] && [ "$_sm_bad" -gt 0 ]; then
        echo "[!] add_sus_mount 不可用（上游已 deprecated），标记为不支持"
        caps_downgrade sus_mount
    fi
fi

# 6b. sus_map（mmap 隐藏，/proc/susfs_map）
if [ -f "$CONFIG/sus_map.txt" ]; then
    if ! sus_map_supported; then
        if [ -s "$CONFIG/sus_map.txt" ] && grep -qvE '^[[:space:]]*(#|$)' "$CONFIG/sus_map.txt"; then
            echo "[i] 内核未提供 /proc/susfs_map（需 r18.5+），跳过 sus_map"
        fi
    else
        _map_n=0; _map_ok=0; _map_bad=0
        while IFS= read -r _line || [ -n "$_line" ]; do
            path=$(clean_entry "$_line")
            [ -n "$path" ] || continue
            case "$path" in
                /*) ;;
                *) echo "[!] sus_map 忽略非绝对路径: $path"; continue ;;
            esac
            _map_n=$((_map_n + 1))
            if [ ! -e "$path" ]; then
                echo "[!] sus_map 路径不存在，跳过: $path"
                continue
            fi
            sus_map_add_once "$path"
            case $? in
                0) _map_ok=$((_map_ok + 1)); echo "[+] sus_map $path" ;;
                2) echo "[=] sus_map $path (本次开机已添加，跳过)" ;;
                *) _map_bad=$((_map_bad + 1)); echo "[=] sus_map $path (失败)" ;;
            esac

        done < "$CONFIG/sus_map.txt"
        _rule_fails=$((_rule_fails + _map_bad))
        [ "$_map_n" = "0" ] && echo "[i] sus_map.txt 为空，跳过"
        [ "$_map_ok" -gt 60 ] && echo "[!] sus_map 规则数 $_map_ok 接近上限 64"
        [ "$_map_ok" = "0" ] && [ "$_map_bad" -gt 0 ] && echo "[!] /proc/susfs_map 写入失败，请确认内核支持"
    fi
fi

# 7. try_umount
if [ -f "$CONFIG/try_umount.txt" ]; then
    if ! cap_ok try_umount; then
        if [ "${USING_BACKUP_BIN:-0}" = "1" ]; then
            echo "[i] try_umount 不可用：当前用的是模块备份的旧 ksu_susfs，可能缺该命令"
        else
            echo "[i] 本内核未实现 try_umount 命令，跳过"
        fi
    else
    _tu_ok=0; _tu_bad=0
    while IFS= read -r _line || [ -n "$_line" ]; do
        path=$(clean_entry "$_line")
        [ -n "$path" ] || continue
        case "$path" in
            /*) ;;
            *) echo "[!] 忽略非绝对路径: $path"; continue ;;
        esac
        try_umount_add_once "$path"
        case $? in
            0) _tu_ok=$((_tu_ok + 1)); echo "[+] try_umount $path" ;;
            2) echo "[=] try_umount $path (本次开机已添加，跳过)" ;;
            *) _tu_bad=$((_tu_bad + 1)); echo "[=] try_umount $path (失败)" ;;
        esac
        done < "$CONFIG/try_umount.txt"
        _rule_fails=$((_rule_fails + _tu_bad))
        if [ "$_tu_ok" = "0" ] && [ "$_tu_bad" -gt 0 ]; then
            echo "[!] add_try_umount 实测不可用，标记为不支持"
            caps_downgrade try_umount
        fi
    fi
fi

# 8. hide_modules（统一走 common.sh 的助手）
apply_hide_modules

# 8b. 伪装 uname（只影响用户态看到的内核版本）
# 伪装前先记下真实内核，出问题时可用 ctl.sh restore_uname 还原
save_real_uname
if has_feature CONFIG_KSU_SUSFS_SPOOF_UNAME; then
    if [ "$spoof_uname" = "1" ]; then
        _r=${spoof_uname_release:-default}
        _v=${spoof_uname_version:-default}
        if "$BIN" set_uname "$_r" "$_v" >/dev/null 2>&1; then
            # 命令返回 0 不等于真的生效：回读 uname -r 核对（audit-legacy2 MAJ-2）
            _un_r=$(uname -r 2>/dev/null)
            if [ "$_r" != "default" ] && [ -n "$_r" ] && [ "$_un_r" != "$_r" ]; then
                echo "[!] uname 伪装未生效：命令成功但 uname -r 仍为 $_un_r（要的是 $_r）"
                _rule_fails=$((_rule_fails + 1))
            else
                echo "[i] uname 伪装已生效: $_r / $_v（uname -r=$_un_r）"
                echo "[i] 注意：部分内核只伪装 uname -r，uname -v 可能仍是真实值"
            fi
        else
            echo "[!] uname 伪装设置失败"
            _rule_fails=$((_rule_fails + 1))
        fi
    else
        if "$BIN" set_uname default default >/dev/null 2>&1; then
            echo "[i] uname 伪装已还原"
            save_real_uname force
        fi
    fi
else
    echo "[i] 内核未启用 SPOOF_UNAME，跳过"
fi

# 5c. 仅解锁 BL 可用的隐藏项（临时 root 下早期阶段已过，做了也无效）
if [ "$hide_vendor_sepolicy" = "1" ] || [ "$vold_isolation" = "1" ]; then
    if [ "$(cfg_force_bl)" = "1" ] && [ "$(bootloader_state)" != "unlocked" ]; then
        echo "[!] 已手动确认 BL 已解锁（配置覆盖），实际属性: $(bootloader_state)"
    fi
    if bl_unlocked; then
        if [ "$hide_vendor_sepolicy" = "1" ]; then
            _n=0
            for _p in /vendor/etc/selinux/vendor_sepolicy.cil /vendor/etc/selinux/plat_sepolicy.cil /vendor/etc/selinux/precompiled_sepolicy /system/etc/selinux/plat_sepolicy.cil; do
                [ -e "$_p" ] || continue
                _n=$((_n + 1))
                add_sus_path_safe "$_p"
            done
            [ "$_n" = "0" ] && echo "[i] 未发现 sepolicy 文件，跳过"
        fi
        if [ "$vold_isolation" = "1" ]; then
            _n=0
            for _p in /sdcard/Android/data /sdcard/Android/obb /data/media/0/Android/data /data/media/0/Android/obb; do
                [ -e "$_p" ] || continue
                _n=$((_n + 1))
                add_sus_path_safe "$_p"
            done
            [ "$_n" = "0" ] && echo "[i] 未发现 Android/data 目录，跳过"
        fi
    else
        echo "[i] 未解锁 BL（BL=$(bootloader_state)）：sepolicy / VOLD 隔离在临时 root 下无效，跳过"
    fi
fi

# 5d. GAPPS / DEX2OAT 隐藏
if [ "$hide_gapps" = "1" ]; then
    _n=0
    # 只隐藏 GMS 的数据目录：安装目录不能隐藏 —— PackageManager 的 sourceDir 仍指向它，
    # 隐藏后 App 侧核对会得到「记录在、文件没了」，检测器判定「安装记录与 APK 不符」。
    for _p in /data/data/com.google.android.gms /data/user_de/0/com.google.android.gms               /data/data/com.google.android.gsf /data/user_de/0/com.google.android.gsf               /data/data/com.android.vending /data/user_de/0/com.android.vending; do
        [ -e "$_p" ] || continue
        _n=$((_n + 1))
        add_sus_path_safe "$_p"
    done
    [ "$_n" = "0" ] && echo "[i] 未发现 GAPPS 数据目录，跳过（未装 GMS 或系统属正常）"
fi

if [ "$hide_dex2oat" = "1" ]; then
    if hide_mounts_supported || cap_ok sus_mount; then
        _dex_n=0; _dex_ok=0; _dex_bad=0
        for _dex_m in $(grep -E " (/(system|apex|product)/[^ ]*/oat|/data/dalvik-cache)" /proc/mounts 2>/dev/null | cut -d" " -f2 | sort -u); do
            [ -d "$_dex_m" ] || continue
            _dex_n=$((_dex_n + 1))
            # 优先前缀表；旧内核回退 add_sus_mount
            if hide_mounts_has "$_dex_m"; then
                echo "[=] hide_mounts $_dex_m (已在表中，跳过)"
            elif hide_mounts_add "$_dex_m"; then
                _dex_ok=$((_dex_ok + 1))
                record_own_hide_mount "$_dex_m"
                echo "[+] hide_mounts $_dex_m (dex2oat)"
            else
                sus_mount_add_once "$_dex_m"
                case $? in
                    0) _dex_ok=$((_dex_ok + 1)); echo "[+] sus_mount $_dex_m (dex2oat)" ;;
                    2) echo "[=] sus_mount $_dex_m (本次开机已添加，跳过)" ;;
                    *) _dex_bad=$((_dex_bad + 1)); echo "[=] sus_mount $_dex_m (失败)" ;;
                esac
            fi
        done
        _rule_fails=$((_rule_fails + _dex_bad))
        [ "$_dex_n" = "0" ] && echo "[i] 未发现 dex2oat 挂载，跳过"
        # 前缀表上限 64（r18.5+）；超过就只能靠 sus_path 覆盖，写日志提醒
        [ "$_dex_ok" -gt 60 ] && echo "[!] dex2oat 前缀数 $_dex_ok 接近/超过 hide_mounts 上限 64，部分可能未生效"
        # 全部失败说明命令实际不可用（特性位谎报），降级后不再尝试
        if [ "$_dex_ok" = "0" ] && [ "$_dex_bad" -gt 0 ]; then
            echo "[!] add_sus_mount 实测不可用，标记为不支持"
            caps_downgrade sus_mount
        fi
    else
        echo "[i] 本内核未实现挂载命令（无 hide_mounts 节点且 add_sus_mount 不可用），跳过 DEX2OAT 隐藏"
    fi
fi

# 5e. Scene 痕迹（/dev 下随机命名的目录，内含 scene_mode_category）
if [ "$hide_scene" = "1" ]; then
    # Scene 的目录名每次开机都变，创建时机也可能晚于本脚本。
    # 只有开机自动应用才值得等（最多 3 轮 5 秒）；WebUI 手动保存时扫一次就走，
    # 否则每次「保存并应用」都要干等 10 秒，而目录往往根本不存在。
    _sc_tries=0
    _sc_n=0
    _sc_max=1
    [ "${AUTOLOAD:-0}" = "1" ] && _sc_max=3
    while [ "$_sc_tries" -lt "$_sc_max" ]; do
        for _sc_f in /dev/*/scene_mode_category; do
            [ -e "$_sc_f" ] || continue
            _sc_d=${_sc_f%/scene_mode_category}
            _sc_n=$((_sc_n + 1))
            add_sus_path_safe "$_sc_d"
            add_sus_path_safe "$_sc_f"
        done
        [ "$_sc_n" -gt 0 ] && break
        _sc_tries=$((_sc_tries + 1))
        [ "$_sc_tries" -lt "$_sc_max" ] && sleep 5
    done
    if [ "$_sc_n" = "0" ]; then
        echo "[i] 未发现 scene 痕迹，跳过（可稍后在 WebUI 点「重扫 Scene」）"
    fi
fi


# 5f. 自动 try_umount：识别 KernelSU 模块挂载（overlay 源为 KSU，或 bind 自 /data/adb）
# 开启后始终过滤真实分区（erofs/ext4/f2fs/squashfs/vfat 且根为 /），避免误卸系统分区；
# 登记结果写入 state/try_umount_auto.txt，便于排查与回滚。
if [ "$auto_try_umount" = "1" ]; then
    if ! cap_ok try_umount; then
        echo "[i] 本内核未实现 try_umount 命令，跳过自动 try_umount"
    else
        [ "$skip_legit_mounts" = "0" ] && echo "[i] 已强制过滤真实分区（该保护不可关闭）"
        _n=0; _ok=0; _bad=0
        _list="$STATE/try_umount_auto.txt"
        : > "$_list" 2>/dev/null
        while read -r _id _parent _dev _root _mp _rest; do
            [ -n "$_mp" ] || continue
            _fs=$(printf '%s' "$_rest" | awk '{for(i=1;i<=NF;i++) if($i=="-"){print $(i+1); exit}}')
            _src=$(printf '%s' "$_rest" | awk '{for(i=1;i<=NF;i++) if($i=="-"){print $(i+2); exit}}')
            _hit=0
            case "$_src" in KSU|shared) _hit=1 ;; esac
            case "$_root" in *"/adb/"*) _hit=1 ;; esac
            case "$_mp" in /data/adb|/data/adb/*) _hit=1 ;; esac
            [ "$_hit" = "1" ] || continue
            # 真实分区一律跳过（不可通过配置关闭）
            is_legit_partition_mount "$_fs" "$_root" && continue
            [ -e "$_mp" ] || continue
            _n=$((_n + 1))
            try_umount_add_once "$_mp"
            _tu_rc=$?
            if [ "$_tu_rc" = "2" ]; then
                echo "[=] try_umount $_mp (本次开机已添加，跳过)"
            elif [ "$_tu_rc" = "0" ]; then
                _ok=$((_ok + 1))
                printf '%s\n' "$_mp" >> "$_list" 2>/dev/null
                echo "[+] try_umount $_mp (auto)"
            else
                _bad=$((_bad + 1))
                echo "[=] try_umount $_mp (auto, 失败)"
            fi
        done < /proc/1/mountinfo
        # 全部失败说明命令实际不可用，标记为不支持，避免下次重复刷失败日志
        if [ "${_ok:-0}" -eq 0 ] && [ "${_bad:-0}" -gt 0 ]; then
            echo "[!] try_umount 实际不可用（全部失败），标记为不支持"
            caps_downgrade try_umount
        fi
        if [ ! -r /proc/1/mountinfo ]; then
            echo "[!] 读不到 /proc/1/mountinfo，无法判断模块挂载"
        elif [ "$_n" = "0" ]; then
            echo "[i] 未发现模块挂载，跳过自动 try_umount"
        fi
    fi
fi

backup_config

# 9. WebUI 兼容标记 + 统计
touch_marker

# 9b. 关掉开关不会自动撤销旧规则：只在「配置确实变过 + replace_rules=0」时提示一次
# （replace_rules=0 是只追加，用户以为关掉就没了）（audit-legacy2 MAJ-3）
_cfg_digest=$( { cat "$CONFIG/config.ini" "$CONFIG/sus_path.txt" "$CONFIG/sus_path_loop.txt" \
                    "$CONFIG/hide_modules.txt" 2>/dev/null; } | cksum 2>/dev/null | awk '{print $1"-"$2}')
_dg_old=$(cat "$STATE/.cfg_digest" 2>/dev/null)
if [ "$replace_rules" = "0" ] && [ -n "$_cfg_digest" ] && [ "$_cfg_digest" != "$_dg_old" ] \
   && [ -s "$STATE/our_paths.txt" ]; then
    echo "[i] 提示：replace_rules=0（只追加），关掉某个隐藏开关不会自动撤销内核里的旧规则"
    echo "    本模块已记录 $(grep -c . "$STATE/our_paths.txt" 2>/dev/null) 条自己写入的规则；如需清理请把 replace_rules 设为 1"
fi
[ -n "$_cfg_digest" ] && printf '%s\n' "$_cfg_digest" > "$STATE/.cfg_digest" 2>/dev/null

RULES=$(grep '^path=' /proc/susfs_path 2>/dev/null | grep -v '\[ours:' | sed 's/^path=//' | awk '{print $1}' | sort -u | wc -l | tr -d ' ')
RULES=${RULES:-0}
echo "[i] 当前用户 sus_path 唯一规则数: $RULES"
printf '%s\n' "${_rule_fails:-0}" > "$STATE/apply_fails" 2>/dev/null

# 8c. Probe PID Guard：配置改了就就地重载/卸载，不必重启
# 可选组件，成败不影响本次 apply 的结果（自己写 state/pid_guard.status）
sh "$MODDIR/pid_guard.sh" "$KMI" >/dev/null 2>&1 || true

if [ "${_rule_missing:-0}" -gt 0 ] 2>/dev/null; then
    echo "[i] 另有 $_rule_missing 条规则的目标路径不存在，已跳过（不算失败）"
    echo "    临时/可能不存在的路径请改用 sus_path_loop.txt，它会在路径出现后自动隐藏"
fi

if [ "${_rule_fails:-0}" -gt 0 ] 2>/dev/null; then
    echo "[!] 本次有 $_rule_fails 条规则下发失败，详见 apply.log"
    set_description "⚠️ 运行中 | $RULES 条规则 | $KMI | $_rule_fails 条失败${_rule_missing:+（另有 $_rule_missing 条路径不存在）}（见 apply.log）"
    echo "=== apply done with warnings ==="
    _set_apply_result partial
    # 5 = 已执行但部分规则失败：调用方可视为"本 boot 已完成"，不能当全部成功
    exit 5
fi
if [ "${RULES:-0}" = "0" ] && [ "${_rule_missing:-0}" -gt 0 ] 2>/dev/null; then
    echo "[!] 没有任何规则被下发（$_rule_missing 条路径不存在），判为 partial"
    set_description "⚠️ 运行中 | 0 条规则 | $KMI | $_rule_missing 条路径不存在未下发"
    _set_apply_result partial
    exit 5
fi
if [ "${_rule_missing:-0}" -gt 0 ] 2>/dev/null; then
    set_description "✅ 运行中 | $RULES 条规则 | $KMI | $_rule_missing 条路径不存在未下发"
else
    set_description "✅ 运行中 | $RULES 条规则 | $KMI | ${VERSION:-unknown}"
fi
_set_apply_result success
echo "=== apply ok ==="
exit 0