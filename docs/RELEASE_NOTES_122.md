# LKM SUSFS管理器 1.2.2

两件事：**英文界面** 和 **Magisk 兼容**。

## 英文界面

默认跟随系统语言：英文系统自动显示英文，中文系统保持中文。也可以在「关于」页手动切换（写 localStorage 后重载页面）。

| 项 | 说明 |
|---|---|
| 覆盖范围 | 235 条文案：状态页 / 配置页 / 日志页 / 关于页、开关说明、确认弹窗、横幅提示、错误文案、模块运行描述 |
| 动态内容 | 版本号、路径、规则数等按模式翻译，例如 `✅ Running \| 3 rules \| 6.6.77 \| v2.3.0-r18.8` |
| 不误翻 | 没有词典条目的内容原样保留，日志正文、路径、包名不会被改写 |
| 切换方式 | 关于页「Language」→ 中文 / English，选中后整页重载，不残留中英混排 |

新增一条离线测试（`tools/test_i18n.sh` + `tools/i18n_audit.js`）：校验 index.html 的每段文案与占位符、app.js 每段渲染文案都有译文，并断言行内标签拼接后英文片段之间必须有空格——避免出现 `Forfake-lockeddevices` 这种中文直拼后遗症。

## Magisk 兼容

之前只认 KernelSU 系列，Magisk 用户装不上，也不会有开机自动应用。

| 项 | 说明 |
|---|---|
| 安装 | 安装脚本放行 `MAGISK_VER` / `MAGISK_VER_CODE` / `/data/adb/magisk`，不再直接 abort |
| 开机入口 | 新增 `service.sh`：Magisk 没有 `boot-completed`，规则在 late_start 应用；KernelSU / APatch 已有 `boot-completed.sh`，这里直接跳过，不会重复执行 |
| 启动守卫 | 只有应用成功（rc=0）才清除守卫标记，与 KernelSU 路径一致；否则 Magisk 下守卫永远不会清除，每次开机都会误判「上次没启动完成」而暂停自动加载 |
| 权限 | 安装脚本给 `service.sh` 设 0755 |

**说明**：我没有 Magisk 真机，Magisk 这条路径属于新增实现、未在真机实测（KernelSU / SukiSU 路径的回归测试通过）。安装与开机应用按 Magisk 生命周期实现（`post-fs-data` + `service`），遇到问题请反馈日志。

## 发布前审计修复（1.2.2）

首轮只读审计发现并修复了两个高危问题：

1. **Action 按钮假成功**：`action.sh` 之前只看"LKM 是否就绪"，apply 因锁忙/文件被改/loading 残留而跳过时仍打印 `[OK] 完成` 并清掉启动守卫。现在改为 **apply rc=0 且内核侧就绪** 才算成功；失败时打印两个 rc 并保留守卫。
2. **helper 变量互相覆盖**：脚本为兼容老式 sh 没有用 `local`，`record_own_hide_mount` 写调用方的 `_n`、`record_our_path` 写调用方的 `_f`。后果：开启 `hide_dex2oat` 且命中 ≥2 条挂载时 apply 会被算术错误中途打断；Scene 第二条规则写错路径。现在 helper 内部变量全部改成独立名字，循环变量也改为 `_dex_*` / `_sc_*` / `_rs_*`。

附带修复：
- `ctl.sh load/apply` 手动路径成功后主动清启动守卫，与 Action 行为一致（之前成功也不清）
- `apply.sh` 的 `state/loading` 残留改为返回 3（跳过），boot-completed 不会再把"没执行"当成功
- `load.sh` 返回 2（未匹配内核）时不再被 apply 覆盖成 "LKM 加载失败"
- 去重账本清理从"内核已就绪"分支移到真实 insmod 成功路径

回归测试：新增 `test_action_entry.sh`（9 断言）与 `test_helper_scope.sh`（5 断言），总计 **25 项离线测试全绿**。

## 审计 P2 修复

- 规则失败统计：apply 结束时写 `state/apply_fails`，描述改为「⚠️ 运行中 … N 条失败」，Action 也会提示
- 管理器判定改为进程优先（magiskd / apd），目录残留不再误判
- 完整性校验新增 `.cf.ok` 缓存：同一 boot 只完整哈希一次，后续阶段复用；文件变动会自动失效
- 注释只认行首或空白后的 `#`，路径里的 # 不再被截断
- 过期锁接管补写 boot_id；`susfs_path_del` 改为回读确认；连续失败 3 次自动暂停自动加载
- 安装时 KMI 未匹配会明确提示「未安装 LKM」

## 状态模型与配置三态（外部 review 第二轮采纳）

- `kernel_config_get` 改为三态：值 / n（明确 not set）/ absent（配置可读但无此键）/ unknown（配置不可读）；不再把空串当 n
- `apply` 写出 `state/apply_result`（not_tested / success / partial / skipped / failed），与“功能是否生效”分离
- `boot-completed` / `service` 在 rc=0/5 时写 `state/boot_stage_completed`（boot_id + 时间）
- `ctl.sh status` / `backend_probe` 新增：backend_kind、backend_interface_detected、root_userland、kernelpatch_runtime=unknown、abi_match=unknown、effect_verified=not_tested、crash_evidence、tool_query、apply_result、boot_stage_completed
- “builtin”表述收紧为“检测到管理接口”，不代表功能完整可用；ABI 与功效仍需目标环境验证
- 降级说明：pstore not_observed ≠ 无崩溃；AVB 元数据保留 ≠ 签名验证通过
## 后端契约探测（内置 SUSFS / KSU 依赖）

- 新增 `ctl.sh backend_probe`：一次性输出 内核/ KMI / 管理器 / CONFIG_MODULES/KALLSYMS_ALL/KSU/KSU_SUSFS/各 SUSFS 特性位 / susfs_kind / /proc 节点 / 工具 version+variant+features / ksyms 计数 / pstore 状态
- status 增加 `config_ksu=`、`config_ksu_susfs=`
- 内置 SUSFS 且 CONFIG_KSU 明确未启用时，apply 打印「uid/挂载判定可能退化」警告（非阻塞）
- 说明：上游 susfs4ksu 补丁基于 KernelSU 内核树；LKM 移植版通过可选 kallsyms 解析 KSU 判定函数证明可解耦，KSU 集成是增强而非必需
- 注意：SUSFS hide_syms 开启时 /proc/kallsyms 里的 susfs_/ksu_ 符号可能被隐藏，ksyms 计数不能单独作为后端判据
## 外部 review 适配（第三轮：APatch 兼容性讨论）

- **内置后端判定收紧**：不再只看 ksu_susfs show version，改为 握手成功 + 版本/特性输出非空 + 至少一个 /proc/susfs_* 节点；避免把不匹配的工具误判成内置 SUSFS
- **部分成功可区分**：规则部分失败时 apply 返回 rc=5，boot-completed/service/ctl/action 将 0/5 都视为本 boot 已完成并提示失败条数；不再用单一 exit 0 表达验收
- **状态语义分离**：status 增加 apatch_userland 与 kernelpatch_kernel=unknown，明确「用户态线索」不等于「内核已运行 KernelPatch」
- **安装提示**：检测到内核已提供 /proc/susfs_* 时提示「只管理规则，不依赖外挂 LKM」
- **Route A 澄清（文档）**：此前失败的是 kernelpatch.ko（框架 LKM），不是 susfs_guard_lkm；本机 susfs_guard_lkm 已在同厂商内核上成功加载，kpimg 补丁不触碰 ksymtab/vermagic → LKM 路线未被证伪，未知点在运行时共存
## 第二轮审计修复（blocker + major）

- **blocker**：pstore 崩溃门禁原先 `exit 0` + `pause_autoload`，调用方会当成功清掉守卫/暂停标记，导致「崩一次、空跑一次」循环。改为 `exit 3`（跳过），并新增 `autoload_paused` 早退同样返回 3
- **pstore 判据收紧**：不再只看「同文件出现 susfs」，要求同文件同时有 panic/oops 与模块栈字样（`susfs_guard_lkm` / `susfs_allinone`）；扫描全部 pstore 文件；新增内容指纹 + `ctl.sh crash_ack`，`resume_autoload` 会自动记录已确认指纹，避免同一记录反复告警
- **APatch 判定改强特征**：`pidof apd`、`/data/adb/apd`、`ap/bin/apd`、`ap/package_config` 任一命中才算；只有残留 `/data/adb/ap` 目录不再误判（避免 KernelSU/Magisk 用户被默认拦截、avc_spoof 被误关）
- **预检重构**：`kernel_load_preflight()` 统一处理 `modules_disabled` / `CONFIG_MODULES` / `MODULE_SIG_FORCE`；`/proc/config.gz` 为空或不可解析时跳过而不是误杀；确定性失败直接 `pause_autoload`
- **放行标记不再丢**：`allow_lkm_on_kernelpatch` 加入升级白名单与配置备份/恢复；status 增加 `allow_lkm=`
- **手动路径也拦截**：APatch/KernelPatch 未放行时，「加载并应用 / 仅应用配置」同样被拒绝并提示 `ctl.sh allow_lkm`，避免 UI 绕过后门
- **ctl 加固**：`allow_lkm` 写后校验、`disallow_lkm` 补 `_cf_gate`、新增 `crash_ack`；status 的 `kernelpatch` 改为实时判定
- **测试**：`test_apatch_guard.sh` 重写为 25 条断言，覆盖强特征判定、pstore 5 种边界 + ack、预检三态、放行开关、以及 **apply 门禁端到端回归**（断言 pstore 命中时 rc=3 且守卫/暂停不被清）
## APatch 防护（默认不外挂 LKM + 崩溃自停）

针对「在 APatch/KernelPatch 上外挂 SUSFS LKM 后崩溃/重启」的风险，增加四层保护：

- **默认不外挂**：检测到 APatch/KernelPatch 且内核侧无 SUSFS 时，自动路径不加载、手动操作也拒绝；要尝试外挂需先 `ctl.sh allow_lkm`
- **崩溃自停**：若上一次启动的 pstore/ramoops 中同时出现 panic/oops 与 susfs 字样，自动暂停自动加载，需 `ctl.sh resume_autoload` 恢复
- **内核限制预检**：`modules_disabled=1`、未编译 `CONFIG_MODULES`、`MODULE_SIG_FORCE` 命中时直接给出原因，不再反复重试
- **诊断**：`ctl.sh crash_report` 显示崩溃疑似状态与 pstore 文件；`ctl.sh allow_lkm` / `disallow_lkm` 控制放行

KernelSU / Magisk 的正常使用路径不受影响。

## APatch / KernelPatch 共存安全模式

静态分析（WORKLOG §26/§27）确认：kpimg 会 hook SELinux 审计/策略面（`avc_denied`、`slow_avc_audit`、`avc_has_perm`、`selinux_hide` 等），与本模块的 `avc_spoof` 重叠。因此：

- 检测到 APatch / KernelPatch（`/data/adb/ap` 或管理器是 APatch）时，**自动关闭 avc_spoof**，并在 apply.log 说明
- 其余功能（sus_path / hide_mounts / sus_map / try_umount / uname / cmdline / 模块隐藏）保留
- 状态页 API 新增 `kernelpatch=` / `coexist_mode=` 字段，便于排查
- 无法运行时关闭的残留项：SUSFS LKM 内置 `hide_syms`（如 APatch 下 KPM 解析异常，先停本模块验证）

## 内核内置 SUSFS 适配（面向 APatch / 自编内核）

SUSFS 不只有 LKM 一种形态：按上游补丁的 `CONFIG_KSU_SUSFS_*` 特性位，它也可以直接编进内核（`SUS_PATH` / `SUS_MOUNT` / `SUS_KSTAT` / `SPOOF_UNAME` / `SPOOF_CMDLINE_OR_BOOTCONFIG` / `OPEN_REDIRECT` / `SUS_MAP` / `HIDE_KSU_SUSFS_SYMBOLS` / `ENABLE_LOG` 等）。之前模块只认 LKM 的 `/proc` `/sys` 标记，内核内置 SUSFS 时会被误判成“未加载”，然后重复 insmod。

现在改成三层判断（`common.sh` 的 `_susfs_detect`）：

| 类型 | 判定 | 行为 |
|---|---|---|
| `lkm` | `/proc/susfs_path` 或 `/sys/module/susfs_guard_lkm` / `susfs` 存在 | 跳过加载，直接管理规则 |
| `builtin` | 无 LKM 标记，但 `ksu_susfs show version` 握手成功（内置接口在） | 跳过加载，直接管理规则 |
| `none` | 两者都没有 | 按原流程加载 LKM |

配套改动：
- `apply.sh` / `load.sh` / `action.sh` / `ctl.sh` 全部改用 `susfs_kernel_ready`，不再只看 LKM 标记
- `ctl.sh status` 新增 `susfs_kernel=lkm|builtin|none`，`ctl.sh loadstatus` 新增 `kernel=` 字段，`ctl.sh diag` 输出 `susfs_kernel` 与 `lkm_marker`
- 安装脚本增加内核预检（只提示不阻断）：内核没开 `CONFIG_MODULES` / 缺 `CONFIG_KALLSYMS` / 缺 `CONFIG_KPROBES` / 强制模块签名时给出明确提示
- 新增离线测试 `test_susfs_kind.sh`：LKM 标记、内置握手、两者皆无、握手失败、标记优先 5 种情况

这样在「内核编入 SUSFS（含与 KPM 共存的构建）」的设备上，模块不会再去撞 LKM，而是直接走规则管理——这也是 APatch 用户唯一现实的 SUSFS 用法。

## APatch 识别（未实机验证）

1.2.2 加了一层 APatch 适配，但**不宣称兼容**：

- 安装脚本先认 APatch：`APATCH` / `KERNELPATCH` / `/data/adb/ap`（APatch 会把 `MAGISK_VER_CODE` 设成 27000，不先判断就会被误标成 Magisk），并打印真实管理器名
- 安装时提示「APatch 未实机验证：本模块需要加载 SUSFS LKM」
- 运行期失败描述按管理器区分：APatch 下缺接口写 `❌ APatch: 未找到 SUSFS 接口（内核需集成 SUSFS 或允许加载 SUSFS LKM）`，而不是笼统的「ksu_susfs 缺失」
- 关于页标注：APatch 需要内核已集成 SUSFS 或允许加载 SUSFS LKM；WebUI 需第三方宿主（如 KsuWebUI）
- 开机阶段：APatch 与 KernelSU 系列一样走 `post-fs-data → boot-completed`（APatch 官方文档确认支持 `boot-completed.sh`）

**仍未验证的部分**：APatch 内核上 SUSFS LKM 能否加载（KernelPatch 会占用内核 hook 空间）。本机 BL 锁 + 临时 root 无法刷 APatch，KernelPatch 的 LKM 交付路径又被符号/模块签名保护拦住，所以这一项要等真机。

## 关于页重写

原来的「关于」只写了 KernelSU 系列，1.2.2 起同时支持 Magisk，所以整页重写：

- 管理器清单：KernelSU 官方版、SukiSU、ReSukiSU、KernelSU Next、Magisk
- 开机链路按管理器区分：KernelSU 系列 `post-fs-data` → `boot-completed`；Magisk `post-fs-data` → `service`（late_start）
- 状态页「工作方式」同步更新，不再写成只有 `boot-completed`
- 注明 WebUI 支持中文 / English

## 修的问题

- 关于页里 LKM 版本号写死成 `v2.3.0-r18.6`，实际从 1.2.1 起就是 `v2.3.0-r18.8`，已改。
- `module.prop` 描述补上 Magisk。

## 升级

管理器里覆盖安装即可，配置与规则文件全部保留。KernelSU 系安装到 `modules_update`，**需要重启一次生效**；重启后 LKM 会重新加载，规则重新应用。

- 文件：`susfs_allinone-1.2.2.zip`
- 大小：11064151 字节
- SHA256：`978d3424604238d64978af8ad28d56e6d0a288509e56b35e1d123120fad2b020`
- 离线测试：18 项全绿

## 已知问题（外部反馈，未复现）

**r18.8 + NeoZygisk 可能触发 zygote 循环重启**

- 反馈来源：酷安 [feed/74905454](https://www.coolapk.com/feed/74905454)（OnePlus PKG110 / ColorOS 16 / 内核 6.1.141-android14-11 / KernelSU LKM / NeoZygisk v2.4 / SUSFS LKM Loader）
- 现象：开机后所有 Zygisk 模块失效，NeoZygisk 报 `dlopen ... /data/adb/neozygisk/lib64/libzygisk.so not found`（文件实际存在），dmesg 里 zygote 被反复杀掉重启；回退 r18.6 正常
- 推断：NeoZygisk 在 zygote 入口 ptrace 注入时 dlopen 被内核路径隐藏拦截；本模块默认隐藏 `/data/adb`，因此 **NeoZygisk 用户有风险**
- 建议：
  - 用 NeoZygisk 时不要隐藏 `/data/adb`（至少把 `/data/adb/neozygisk` 排除）
  - 或改用 Zygisk Next
  - 或临时回退上游 r18.6 的 `.ko`（升级前先备份当前 ko 与 `susfs_insmod`）
- 我们的测试机使用 Zygisk Next，未复现；本条为外部单机反馈，供参考。
