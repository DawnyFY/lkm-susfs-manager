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

回归测试：新增 `test_action_entry.sh`（9 断言）与 `test_helper_scope.sh`（5 断言），总计 **24 项离线测试全绿**。

## 审计 P2 修复

- 规则失败统计：apply 结束时写 `state/apply_fails`，描述改为「⚠️ 运行中 … N 条失败」，Action 也会提示
- 管理器判定改为进程优先（magiskd / apd），目录残留不再误判
- 完整性校验新增 `.cf.ok` 缓存：同一 boot 只完整哈希一次，后续阶段复用；文件变动会自动失效
- 注释只认行首或空白后的 `#`，路径里的 # 不再被截断
- 过期锁接管补写 boot_id；`susfs_path_del` 改为回读确认；连续失败 3 次自动暂停自动加载
- 安装时 KMI 未匹配会明确提示「未安装 LKM」

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
- 大小：11058235 字节
- SHA256：`465e086ec6cb76e109ac79c727069f6b8ee5f5a9a4861f326bb01c8012702ada`
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
