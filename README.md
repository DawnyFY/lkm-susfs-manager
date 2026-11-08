# LKM SUSFS管理器

<p align="center">
  <b>KernelSU 系列 · Magisk · APatch（实验性）</b><br>
  <b>SUSFS LKM 自动匹配 / 加载 / 规则管理</b><br>
  <sub>不再只面向 KernelSU 系；适配多种 root 管理器的开机阶段</sub>
</p>

<p align="center">
  <img alt="License" src="https://img.shields.io/badge/license-GPL--2.0-blue.svg">
  <img alt="Component" src="https://img.shields.io/badge/component-AGPL--3.0-orange.svg">
  <img alt="Arch" src="https://img.shields.io/badge/arch-arm64-lightgrey.svg">
  <img alt="KMI" src="https://img.shields.io/badge/KMI-8%20targets-green.svg">
  <img alt="Managers" src="https://img.shields.io/badge/managers-KernelSU%20%7C%20Magisk%20%7C%20APatch-blueviolet.svg">
  <img alt="Release" src="https://img.shields.io/github/v/release/DawnyFY/lkm-susfs-manager?color=brightgreen">
</p>

---

一个**多管理器**的 SUSFS LKM 模块：**自动匹配 KMI → 加载 SUSFS LKM → 下发规则 → 状态写回模块描述**，附带中文 MIUIX WebUI。

它不再只适用于 KernelSU 系：

- **KernelSU 系列**：官方 KernelSU / SukiSU / ReSukiSU / BakaSU / KernelSU Next
- **Magisk**：按 Magisk 的 late_start 阶段应用规则
- **APatch / KernelPatch**：**实验性支持**，默认安全拒绝外挂 LKM，需显式放行；真机尚未验收

SUSFS 在 LKM 形态下每个 KMI 对应一个 `.ko`。手动流程是：查内核版本 → 找对应 `.ko` → `insmod` → 一条条往 `/proc/susfs_*` 写规则 → 每次重启重来。这个模块把这些全包了。

> **实验性项目。** 已在 Xiaomi 15 Ultra / Android 16 / kernel 6.6.77 / SukiSU Ultra 环境做冷启动与热重启验证；Magisk 只做了代码适配，未做真机冷启动；APatch 只在 QEMU GKI 验证模块路径，**真机未验收**。刷机与 root 有风险，请自行评估恢复手段。

---

## 目录

- [支持矩阵](#支持矩阵)
- [为什么需要它](#为什么需要它)
- [功能](#功能)
- [支持的 KMI](#支持的-kmi)
- [要求](#要求)
- [安装](#安装)
- [APatch 实验性支持](#apatch-实验性支持)
- [配置](#配置)
- [WebUI](#webui)
- [安全须知](#安全须知)
- [验证记录](#验证记录)
- [已知限制](#已知限制)
- [常见问题](#常见问题)
- [与上游项目的关系](#与上游项目的关系)
- [反馈与支持](#反馈与支持)
- [致谢](#致谢)
- [许可证](#许可证)
- [免责声明](#免责声明)

---

## 支持矩阵

| 管理器 | 适配 | 验证状态 | 开机阶段 |
|---|---|---|---|
| KernelSU 官方 / SukiSU / ReSukiSU / BakaSU / KernelSU Next | 完整 | **SukiSU 实机冷启动 + 热重启验证**；其余代码兼容，未逐一实机 | `post-fs-data` → `boot-completed` |
| Magisk | 完整 | 代码路径适配，**未做真机冷启动验证** | `post-fs-data` → `service`（late_start） |
| APatch / KernelPatch | **实验性** | **仅 QEMU GKI 验证**；真机未验收 | `post-fs-data` → `boot-completed`，默认拒绝外挂 LKM |

说明：

- 本模块的核心能力是 **SUSFS LKM 加载 + 规则下发**，不依赖某个管理器的专属用户态接口；管理器差异主要在**开机阶段**与**二进制路径**。
- 规则工具优先使用管理器自带的 `ksu_susfs`，不可用时回退到模块内置备份，不覆盖原文件。
- APatch 的“支持”是**实验性路径**，不等于“已兼容”；详见 [APatch 实验性支持](#apatch-实验性支持)。

## 为什么需要它

手动加载 SUSFS LKM 的痛点是版本匹配和重复劳动：

1. 内核字符串与 KMI 对应关系不直观，尤其厂商自改内核（无 `-androidXX-` 标记、带 `-dirty`）；
2. LKM 加载后还要逐条写 `/proc/susfs_*` 规则；
3. 不同管理器的开机阶段不同：KernelSU/APatch 有 `boot-completed`，Magisk 只有 `service`（late_start）；
4. 未解锁 BL 的临时 root 常出现 **late-load**：`post-fs-data` 被跳过，LKM 根本没加载。

本项目的适配：

- **按真实内核匹配 KMI**：优先 `/proc/version`，回退开机快照，最后才用 `osrelease`；
- **按管理器选择阶段**：KSU 系 / APatch 走 `post-fs-data` → `boot-completed`；Magisk 走 `post-fs-data` → `service`；
- **late-load 兜底**：检测到 LKM 未加载时，在 `boot-completed` 阶段补一次 `load.sh manual`；
- **启动守卫**：加载前落标记，异常重启后自动暂停自动加载，避免反复 bootloop；
- **APatch 共存防护**：默认不自动外挂 LKM，避免与 kpimg 冲突。

## 功能

- **8 个 KMI 自动匹配**（android12-5.10 ～ android17-6.18），带 `-androidXX-` 标记优先；**无 Android tag 的 5.15 内核支持按 SDK 自动消歧**（SDK 33/34 → android13/14-5.15，仅在对应 `.ko` 已打包时采用）。
- **多管理器开机阶段**：KSU 系 / APatch 的 `post-fs-data` / `boot-completed`，Magisk 的 `post-fs-data` / `service`；任一阶段失败会写日志，不静默。
- **APatch / KernelPatch 检测**：识别 `/data/adb/ap`、`apd` 等特征；检测到 KernelPatch 时自动关闭与之重叠的 `avc_spoof`。
- **APatch 默认安全策略**：自动加载跳过、手动加载拒绝；需要时用 `ctl.sh allow_lkm` 或 WebUI 显式放行。
- **KernelPatch 内核运行时探测**：读取 dmesg 的 `KernelPatch Version:` banner；dmesg 不可读时显示 `unknown`，不误报 0/1。
- **late-load 兜底 + 启动守卫 + pstore 崩溃暂停**：临时 root / 半加载 / 上次崩溃场景都有对应保护。
- **规则管理**：`sus_path`、`sus_mount`、`try_umount`、`hide_modules`、`hide_sus_mnts`、AVC 日志伪装。
- **扩展隐藏（默认全关）**：KSU LOOP、REVANCED / YouTube、自定义 ROM、COMPAT MATRIX、GAPPS、DEX2OAT、Scene 痕迹、CMDLINE 伪装。
- **中文 / 英文 MIUIX WebUI**：状态、配置、日志、关于；无外部 CDN，断网可用；APatch 环境额外显示 APatch 卡片。

## 支持的 KMI

| KMI | 内核版本 | 状态 |
|---|---|---|
| `android12-5.10` | 5.10 | 打包，未实机验证 |
| `android13-5.10` | 5.10 | 打包，未实机验证 |
| `android13-5.15` | 5.15 | 打包，未实机验证 |
| `android14-5.15` | 5.15 | 打包，未实机验证 |
| `android14-6.1` | 6.1 | 打包，未实机验证 |
| `android15-6.6` | 6.6 | **已实机验证（KSU 系）** |
| `android16-6.12` | 6.12 | 打包，未实机验证 |
| `android17-6.18` | 6.18 | 打包，未实机验证 |

`.ko` 来自上游 `inforcqb/susfs4ksu-lkm` `v2.3.0-r18.8`，未做修改（哈希见 `provenance.json`）。

无法自动匹配时：

1. 先跑 `ctl.sh kmiinfo` 看诊断；
2. 在 WebUI 配置页填「强制指定 KMI」；
3. 自编译内核（带 `-dirty`、改过符号/CFI）不要反复试，加载失败会写 `load.log`。

## 要求

- **arm64** 设备；
- 受支持的 root 管理器（KernelSU 系 / Magisk / APatch 实验性）；
- 内核 KMI 在上表内，或可用 `force_kmi` 指定；
- 能加载内核模块的 root 环境；临时 root 方案请自行确认可用性；
- APatch 额外要求：内核带 KernelPatch、允许加载 LKM；真实设备请先接受“未验收”风险。

## 安装

### KernelSU 系列

1. Release 下载 `susfs_allinone-<version>.zip`；
2. 管理器「模块 → 从本地安装」；
3. 重启，或执行模块 Action 手动加载；
4. 打开 WebUI 查看状态。

### Magisk

1. Magisk 管理器「模块 → 从本地安装」；
2. 重启（规则在 `service` late_start 阶段应用）；
3. 打开 WebUI 确认 LKM 与规则状态。

> Magisk 路径只做了代码适配，**未做真机冷启动验证**；首次使用请保留旧模块与回退手段。

### APatch

1. 用 APatch 可用的模块安装方式安装本 zip（**APatch Manager 安装流程未实机验证**）；
2. 重启后默认**不会**自动外挂 SUSFS LKM；若内核已内置 SUSFS，无需放行；
3. 只有在内核没有内置 SUSFS、且你明确接受风险时，才执行：
   ```sh
   su -c "sh /data/adb/modules/susfs_allinone/ctl.sh allow_lkm"
   ```
   或使用 WebUI 状态页的 APatch 卡片「放行 LKM」；
4. 放行后手动执行 `load.sh manual` 或重启验证。

升级直接覆盖安装，`config/`、`state/` 会保留。

## APatch 实验性支持

### 适用范围

- 内核由 **KernelPatch / kpimg** 接管；
- 内核没有内置 SUSFS，需要外挂 SUSFS LKM；
- 你愿意承担实验性共存风险，且有恢复手段。

### 已验证什么

- **QEMU GKI（6.6，kpimg d09）**：SUSFS LKM 可加载；规则隐藏/恢复可用。
- **模块级 APatch 路径（QEMU 模拟 `/data/adb/ap`）**：
  - 默认自动加载 → 跳过；
  - 手动加载 → 拒绝；
  - `ctl.sh allow_lkm` → 放行；
  - `load.sh manual` → 加载成功；
  - `apply.sh` → 规则生效；
  - 基线 / patched 各 14/14 断言通过。

### 未验证什么

- 真实 APatch 管理器安装流程、`apd` 用户态、APatch 授权语义；
- 真实 APatch 内核的 ABI / 符号 / CFI / KMI 差异；
- WebUI APatch 卡片在真机上的显示与按钮交互；
- 长期稳定性、卸载/重载、升级路径。

### 风险与默认策略

- **默认不自动加载**，手动加载也拒绝；这是为了防止与 kpimg 冲突导致启动异常。
- 放行属于实验性操作，**可能 bootloop**；只在测试设备上尝试。
- 检测到上次启动有 SUSFS 相关 panic/oops（pstore）时，自动加载会暂停。
- 没有真机日志前，不要把 APatch 路径用于生产/主力设备。

## 配置

`config/config.ini`（纯 `KEY=VALUE`，不会被执行）：

```ini
auto_load=1        # 1=开机自动加载并应用规则；0=仅手动
hide_sus_mnts=1    # 对非 root 进程隐藏 SUS 挂载点
avc_spoof=0        # AVC 日志伪装（默认关闭；KernelPatch 共存时自动关闭）
replace_rules=0    # 0=只追加；1=只清理本模块上次写入的；2=整表清空（慎用）
```

规则文件：

- `config/sus_path.txt`：每行一个路径，`#` 开头为注释；
- `config/sus_mount.txt` / `try_umount.txt`：挂载规则；
- `config/hide_modules.txt`：默认 `kernelsu`；
- `config/sus_map.txt`：隐藏进程 maps 中的真实文件路径。

APatch 放行标记是独立文件 `config/allow_lkm_on_kernelpatch`，不在 `config.ini` 里。

## WebUI

在管理器中打开模块 WebUI：

| 页面 | 内容 |
|---|---|
| 状态 | LKM 版本、KMI、规则数、SELinux、二进制路径、失败计数；APatch 环境额外显示 APatch 卡片 |
| 配置 | 图形化编辑规则与开关；强制 KMI |
| 日志 | `load.log` / `apply.log` 在线查看 |
| 关于 | 版本、致谢、许可证摘要、语言切换 |

APatch 卡片内容：

- APatch 用户态；
- KernelPatch 内核（有版本时显示，如 `已激活 (d09)`）；
- 共存模式；
- SUSFS LKM 放行状态；
- 「放行 LKM / 取消放行」按钮（带风险确认）。

KSU / Magisk 环境不会显示该卡片。

## 安全须知

- **不要重复加载 LKM**：已加载 SUSFS 后，不要再用 Termux / adb 手动 `insmod`；不要同时启用两个会加载 SUSFS 的模块。重复加载可能导致内核 panic / 开不了机。
- **不要执行 `rmmod susfs_guard_lkm`**：上游标注存在 UAF / panic 风险。需要卸载请禁用模块后重启。
- **APatch 默认禁止外挂 LKM**：不要在不了解风险时用 `allow_lkm` 绕过；放行可能 bootloop。
- **未解锁 BL 的临时 root**：重启后 root 不会自动恢复，需重新走你原有的注入流程；这是环境限制。
- **不要**为了“修复模块”去解锁 BL、走 EDL / 9008、刷 boot / init_boot。
- 出问题优先禁用模块、取 `load.log` / `apply.log`；保留旧模块回退。
- 本项目不提供 root、解锁、刷机或绕过安全机制的教程。

## 验证记录

**环境**：Xiaomi 15 Ultra（25019PNF3C）/ Android 16 / kernel 6.6.77（`android15-6.6`）/ SukiSU Ultra 4.3.0 / bootloader 未解锁，临时 root。

### 真机（KSU 系）

| 项目 | 结果 |
|---|---|
| 1.2.3 冷启动 | LKM 加载；`/proc/susfs_*` 9 个；`integrity=ok`；规则 11 |
| 1.2.3 热重启 | LKM / 规则 / 探测 / integrity 仍正常 |
| LSPosed | 冷启动未 connected（临时 root / Zygisk 时序）；热重启后 connected、14 modules |
| APatch 卡片 | KSU 环境正确隐藏 |
| 1.2.3-dev 热回归 | `ctl.sh apply` rc=0、`apply_fails=0`，配置未丢 |

### QEMU GKI

- kpimg + SUSFS LKM：加载、隐藏、`add/del` 恢复；
- 模块级 APatch 路径：默认拒绝 → `allow_lkm` → 加载 → `apply.sh` 隐藏/恢复，基线/patched 各 14/14。

### 离线

- 28/28 测试通过；
- `check_zip` / `check_no_crlf` 通过。

**未验证**：其余 7 个 KMI、Magisk 真机冷启动、APatch 真机全链路、官方 KernelSU / ReSukiSU / BakaSU / KernelSU Next 实机。

## 已知限制

- **APatch 仍是实验性**：真机未验收；APatch Manager 安装、真实 ABI/符号、WebUI 卡片交互都未验证。
- **sus_path 持续隐藏缺口**：目标目录被删除重建后，旧 inode 规则失效；重新挂接原型（≤2s 窗口）未合并。
- **Magisk**：未做真机冷启动验证。
- **dmesg 受限设备**：KernelPatch 探测可能显示 `unknown`，不影响模块加载策略。
- **用户态取 LKM 状态**依赖管理器的 `ksu_susfs` 或模块回退二进制；两者都不可用时只能看日志。
- 未解锁 BL 的临时 root 每次重启都要重新注入，这不是模块能修复的。

## 常见问题

<details>
<summary><b>KMI 匹配失败 / 内核带 -dirty 怎么办</b></summary>

先跑 `ctl.sh kmiinfo`。无 Android tag 的 5.15 内核现在会尝试按 SDK 33/34 自动消歧；仍失败时在 WebUI 配置页填「强制指定 KMI」。自编译内核可能因符号/CFI 不匹配加载失败，不要反复试。
</details>

<details>
<summary><b>APatch 下状态页没有 APatch 卡片</b></summary>

卡片只在检测到 APatch / KernelPatch 时显示。KSU / Magisk 下看不到是正常的。APatch 真机检测特征包括 `/data/adb/ap`、`apd`；若你的 APatch 布局不同，附 `ctl.sh status` 反馈。
</details>

<details>
<summary><b>APatch 下 LKM 不加载</b></summary>

这是默认安全策略。内核已内置 SUSFS 时不需要 LKM；没有内置且你接受风险时，执行 `ctl.sh allow_lkm` 或 WebUI 放行，再手动 `load.sh manual`。放行前先备份、确认有恢复手段。
</details>

<details>
<summary><b>Magisk 下规则没生效</b></summary>

Magisk 没有 `boot-completed`，规则在 `service`（late_start）阶段应用。先看 `apply.log` 与 WebUI 状态；本版本未做 Magisk 真机冷启动验证。
</details>

<details>
<summary><b>会不会覆盖管理器自带的 ksu_susfs</b></summary>

不会。优先使用管理器自带的二进制，仅在无法通信时回退到模块内置备份，且不覆盖原文件。
</details>

<details>
<summary><b>冷启动后 Zygisk / LSPosed 异常</b></summary>

临时 root 冷启动时 Zygisk 可能没在 zygote 前就位；这是环境时序，不是模块问题。按你的流程完成 root 后热重启（soft reboot）再测。模块本身只负责 SUSFS LKM。
</details>

## 与上游项目的关系

本项目**不包含任何自研内核代码**。全部 SUSFS 能力来自以下上游项目，本仓库只做集成与适配：

```
├─ simonpunk / susfs4ksu        原始 SUSFS 内核补丁（GPL-2.0）
│    └─ inforcqb / susfs4ksu-lkm    SUSFS 的 LKM 移植，产出 8 个 KMI 的 .ko + susfs_insmod
│         ├─ 上游自带 loader        susfs_guard_lkm-module-<tag>-arm64.zip（只加载，无规则）
│         └─ 本项目  ← 在本仓库     加载 + 规则下发 + WebUI + 多管理器阶段适配
└─ sidex15 / ksu_module_susfs    ksu_susfs 用户态工具（AGPL-3.0）
```

| 上游 | 仓库 | 版本 | 本项目使用方式 |
|---|---|---|---|
| inforcqb / susfs4ksu-lkm | https://github.com/inforcqb/susfs4ksu-lkm | `v2.3.0-r18.8` | `lib/susfs_guard_lkm-*.ko`（8）、`bin/susfs_insmod`，原样使用 |
| sidex15 / ksu_module_susfs | https://github.com/sidex15/ksu_module_susfs | `v1.5.2-R28` | `bin/ksu_susfs_good`（回退用），原样使用 |
| simonpunk / susfs4ksu | 原始 SUSFS 项目 | — | 经 inforcqb 移植，本项目不直接引用 |

上游自带 loader 只负责加载，不写任何 SUSFS 规则、没有 WebUI；本项目的增量是**规则管理 + 多管理器阶段适配 + late-load 兜底 + 二进制回退**。

## 反馈与支持

提交前请确认：

1. 读过 README 与免责声明；
2. 已确认不是：临时 root 重启后需重新注入、冷启动后 Zygisk 未注入、KMI 不在支持列表；
3. 已准备 `load.log`、`apply.log`、`ctl.sh status` 输出。

| 情况 | 去哪 |
|---|---|
| 模块加载失败、规则没生效、WebUI 报错 | [提交问题](https://github.com/DawnyFY/lkm-susfs-manager/issues/new?template=bug_report.yml) |
| 功能建议 | [功能建议](https://github.com/DawnyFY/lkm-susfs-manager/issues/new?template=feature_request.yml) |
| 使用经验 / 配置分享 | [Discussions](https://github.com/DawnyFY/lkm-susfs-manager/discussions) |
| 内核模块崩溃 / `.ko` 兼容性 | 上游 [inforcqb/susfs4ksu-lkm](https://github.com/inforcqb/susfs4ksu-lkm/issues) |
| `ksu_susfs` 行为问题 | 上游 [sidex15/ksu_module_susfs](https://github.com/sidex15/ksu_module_susfs/issues) |
| 安全漏洞 | 见 `SECURITY.md`，请勿公开开 issue |

问题最小信息：

```
设备型号：
Android / 内核版本（uname -r）：
管理器与版本：
root 类型：临时（未解锁 BL）/ 永久（已解锁 BL）
模块版本：
现象：
load.log / apply.log / ctl.sh status：
```

APatch 反馈请额外附：KernelPatch/kpimg 版本、`kernelpatch_kernel` 值、是否内置 SUSFS、`allow_lkm` 状态。

## 致谢

- **simonpunk** — SUSFS 原作者
- **inforcqb** — [susfs4ksu-lkm](https://github.com/inforcqb/susfs4ksu-lkm)，SUSFS 的 LKM 移植
- **sidex15** — [ksu_module_susfs](https://github.com/sidex15/ksu_module_susfs)，`ksu_susfs` 实现
- **SukiSU Ultra 团队** — 管理器与 late-load 机制
- **旧梦一场雨**（[@hhgbmh8-ux](https://github.com/hhgbmh8-ux)）— 帮忙测试模块

## 许可证

- 本项目脚本、安装器与 WebUI：**GPL-2.0**（`LICENSE`）
- 第三方二进制（详见 `NOTICE`、`provenance.json`）：
  - `lib/susfs_guard_lkm-*.ko`、`bin/susfs_insmod` — inforcqb / `susfs4ksu-lkm` `v2.3.0-r18.8`，GPL-2.0，未修改
  - `bin/ksu_susfs_good` — sidex15 & simonpunk / `ksu_module_susfs` `v1.5.2-R28`，AGPL-3.0，未修改
- 本仓库为上述组件的聚合分发，版权与许可证归原作者所有。

## 免责声明

**安装或使用本项目，即表示你已理解并接受以下内容。**

1. **风险自担**：按“现状”提供，不保证通过检测、不保证稳定；可能导致 bootloop、数据丢失、保修失效。
2. **适用环境有限**：KSU 系仅 SukiSU 环境实机验证；Magisk 未真机验证；APatch 仅 QEMU 验证，真机未验收；其余 KMI 多为上游产物。
3. **与 root / 解锁无关**：本项目不提供 root 获取、bootloader 解锁、漏洞利用或刷机教程；你需自行拥有可加载模块的 root 环境。
4. **明确禁止**：`rmmod susfs_guard_lkm`、为修复模块解锁 BL / EDL / 刷 boot、在生产机首次尝试、无备份安装。
5. **合规**：仅用于你拥有操作权限的设备；遵守当地法律与厂商条款；不得用于未授权设备。
6. **第三方组件**：`lib/*.ko`、`susfs_insmod`、`ksu_susfs_good` 的行为与缺陷由原作者负责。
7. **无支持承诺**：Issue/讨论尽力而为；作者可随时停止维护。
8. **许可证优先**：与 `LICENSE` 冲突时以许可证法律条款为准。

---

**如果你不完全理解上述风险，请不要安装。**
