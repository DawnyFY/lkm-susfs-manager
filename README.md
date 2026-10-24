# LKM SUSFS管理器

<p align="center">
  <b>KernelSU 系 · SUSFS LKM 自动匹配 / 加载 / 规则管理</b><br>
  <sub>为「未解锁 BL + 临时 root」场景适配</sub>
</p>

<p align="center">
  <img alt="License" src="https://img.shields.io/badge/license-GPL--2.0-blue.svg">
  <img alt="Component" src="https://img.shields.io/badge/component-AGPL--3.0-orange.svg">
  <img alt="Arch" src="https://img.shields.io/badge/arch-arm64-lightgrey.svg">
  <img alt="KMI" src="https://img.shields.io/badge/KMI-8%20targets-green.svg">
  <img alt="Release" src="https://img.shields.io/github/v/release/DawnyFY/lkm-susfs-manager?color=brightgreen">
</p>

---

一个 KernelSU 系模块：**自动匹配 KMI → 加载 SUSFS LKM → 下发规则 → 状态写回模块描述**，附带中文 MIUIX WebUI。

SUSFS 在 LKM 形态下每个 KMI 对应一个 `.ko`。手动流程是：查内核版本 → 找对应 `.ko` → `insmod` → 一条条往 `/proc/susfs_*` 写规则 → 每次重启重来。这个模块把这些全包了。

> **实验性项目。** 仅在 Xiaomi 15 Ultra / Android 16 / kernel 6.6.77 / SukiSU Ultra 临时 root 环境实测。刷机与 root 有风险，请自行评估恢复手段。

---

## 目录

- [为什么需要它](#为什么需要它)
- [功能](#功能)
- [支持的 KMI](#支持的-kmi)
- [要求](#要求)
- [安装](#安装)
- [配置](#配置)
- [WebUI](#webui)
- [安全须知](#安全须知)
- [测试记录](#测试记录)
- [构建](#构建)
- [常见问题](#常见问题)
- [反馈与支持](#反馈与支持)
- [与上游项目的关系](#与上游项目的关系)
- [致谢](#致谢)
- [许可证](#许可证)
- [免责声明](#免责声明)

---

## 为什么需要它

未解锁 bootloader 的机型（例如小米 15 Ultra）获取 root，通常走这条链：

```
fastboot 注入 ABL cmdline 漏洞 → 系统以 SELinux permissive 启动 → SukiSU late-load 提权
```

由此得到的 root 有两个特征：

1. **临时性**：每次开机都要重新走一遍，不是永久 root；
2. **late-load 注入**：内核侧 `post-fs-data` 阶段会被整个跳过（logcat 中为 `post-fs-data skipped (late load)`）。

第 2 点是最容易踩坑的地方：多数 SUSFS 模块默认自己能在 `post-fs-data` 里加载 LKM，但在 late-load 环境下该阶段根本不执行，结果就是**模块装上显示正常，实际 LKM 未加载、规则未下发**。

本项目的适配：

- **不依赖 `post-fs-data`**：检测到 LKM 未加载时，`boot-completed` 阶段自动走兜底 `load.sh manual`；
- **完整日志**：KMI 选择、`insmod` 输出、符号解析结果逐行记录，失败点一眼可见；
- **加载自限时**：`.ko` 初始化有 20 秒上限，不会拖住启动流程；
- **半加载保护**：上次加载未完成则跳过规则下发，避免留下半成品状态。

## 功能

- **8 个 KMI 自动匹配**（android12-5.10 ～ android17-6.18），按 `/proc/sys/kernel/osrelease` 选择；无法匹配时快速失败，不会误载。
- **两种加载时机**：`post-fs-data`（常规设备）/ `boot-completed` 兜底（late-load 临时 root）；也可通过模块 Action 手动触发，无需重启。
- **规则管理**：`sus_path`、`sus_mount`、`try_umount`、`hide_modules`、`hide_sus_mnts`、AVC 日志伪装开关。
- **扩展隐藏（默认全关）**：隐藏 KSU LOOP 挂载、隐藏 REVANCED / YouTube 模块路径、隐藏自定义 ROM 路径、隐藏 COMPAT MATRIX、伪装 CMDLINE。只隐藏**实际存在**的路径，找不到就跳过并在日志里写明。
- **管理器兼容**：官方 KernelSU / SukiSU / ReSukiSU / KernelSU Next，并兼容 APatch 二进制路径。
- **二进制不覆盖**：优先使用管理器自带的 `ksu_susfs`，仅在无法通信时回退到模块内置备份。
- **中文 MIUIX WebUI**：状态 / 配置 / 日志 / 关于；浅色深色跟随系统；**无外部 CDN**，断网可用。
- **升级友好**：模块 ID 固定为 `susfs_allinone`，升级保留配置；首次安装可尝试导入旧 `susfs4ksu` 配置。

## 支持的 KMI

| KMI | 内核版本 | 状态 |
|---|---|---|
| `android12-5.10` | 5.10 | 打包，未实机验证 |
| `android13-5.10` | 5.10 | 打包，未实机验证 |
| `android13-5.15` | 5.15 | 打包，未实机验证 |
| `android14-5.15` | 5.15 | 打包，未实机验证 |
| `android14-6.1` | 6.1 | 打包，未实机验证 |
| `android15-6.6` | 6.6 | **已实机验证** |
| `android16-6.12` | 6.12 | 打包，未实机验证 |
| `android17-6.18` | 6.18 | 打包，未实机验证 |

`.ko` 来自上游 `inforcqb/susfs4ksu-lkm` `v2.3.0-r18.4`，未做修改（哈希见 `provenance.json`）。

## 要求

- **arm64** 设备
- KernelSU 系列管理器（官方 KernelSU / SukiSU / ReSukiSU / KernelSU Next）
- 内核 KMI 在上表内
- 能加载内核模块的 root 环境；临时 root 方案请自行确认可用性

## 安装

1. 从 [Releases](https://github.com/DawnyFY/lkm-susfs-manager/releases) 下载 `susfs_allinone-<version>.zip`
2. 在管理器中「模块 → 从本地安装」
3. 重启；或进入模块点「执行」手动加载（无需重启）
4. 打开模块 WebUI 查看状态与规则

升级直接覆盖安装即可，配置会自动保留。

## 配置

`config/config.sh`：

```sh
auto_load=1        # 1=开机自动加载并应用规则；0=仅手动
hide_sus_mnts=1    # 对非 root 进程隐藏 SUS 挂载点
avc_spoof=0        # AVC 日志伪装（默认关闭）
replace_rules=1    # 应用前清空未列出的普通 sus_path 规则
```

- `config/sus_path.txt`：每行一个路径，`#` 开头为注释。
- `config/hide_modules.txt`：每行一个模块名，默认 `kernelsu`。
- `config/sus_mount.txt` / `try_umount.txt`：挂载相关规则，默认空。

> 若还有其他工具在写 `sus_path`，把 `replace_rules` 改为 `0`，避免互相清空。

## WebUI

在管理器中打开模块的 WebUI 按钮即可：

| 页面 | 内容 |
|---|---|
| 状态 | LKM 版本、KMI、规则数、SELinux、二进制路径、失败计数 |
| 配置 | 图形化编辑四类规则与开关 |
| 日志 | `load.log` / `apply.log` 在线查看 |
| 关于 | 版本、致谢、许可证摘要 |

## 安全须知

- **不要重复加载 LKM（最容易砖的一条）**：
  - 已经通过模块加载 SUSFS 后，**不要**再用 Termux / adb 手动 `insmod` 或 `susfs_insmod` 加载同一个 `.ko`；
  - 也不要在同一台设备上同时启用两个会加载 SUSFS 的模块（例如本模块 + 上游 `susfs_guard_lkm` 官方模块）；
  - 重复加载是**已知会导致内核 panic / 开不了机**的操作，[上游那边的真实案例](https://www.coolapk.com/feed/74182378)就是刷入模块后又用 Termux 加载，直接崩了。
  - 本模块自身有保护（检测到 `/proc/susfs_path` 或 `/sys/module/susfs_guard_lkm` 就跳过加载，不会叠加），但**外部手动加载绕不过这个保护**。
- **不要执行 `rmmod susfs_guard_lkm`**：上游明确标注存在 UAF / panic 风险，当场卸载可能导致崩溃。需要卸载请在管理器中禁用模块后重启。
- **未解锁 BL 的临时 root 环境**：root 重启后不会自动恢复，需重新走 fastboot 注入 → SELinux 宽容 → 提权。这是环境限制，不是模块问题。
- **不要**为了“修复模块”去解锁 BL、走 EDL / 9008、刷 boot / init_boot。
- 出问题优先在管理器中禁用模块，或执行 Action 获取日志；保留旧模块作为回退。
- 本项目不提供解锁、刷机或绕过安全机制的教程。

## 测试记录

**环境**：Xiaomi 15 Ultra（25019PNF3C）/ Android 16 / kernel 6.6.77（android15-6.6）/ SukiSU Ultra 4.2.1 / **bootloader 未解锁**，fastboot ABL 注入获取临时 root。

| 项目 | 结果 |
|---|---|
| 冷启动（无 root） | 模块零执行，不影响开机 |
| fastboot 注入后自动加载 | KMI 匹配 `android15-6.6`，`init_module` 102 符号全解析 |
| 规则下发 | 8 条 `sus_path` + `hide_modules=kernelsu` 正常写入 |
| 停用旧模块后复测 | 仅本模块即可完成加载与规则下发 |
| Wild Detector 24（实验性检测开） | 环境正常，未检测到修改 |
| Applist Detector | 9 项全部 Not found |
| Ruru V1.1.1 | 9 项全部未发现 |

<p align="center">
  <img src="https://github.com/DawnyFY/lkm-susfs-manager/releases/download/v1.1.6/shot-wilddetector.png" width="250" alt="Wild Detector">
  <img src="https://github.com/DawnyFY/lkm-susfs-manager/releases/download/v1.1.6/shot-applist.png" width="250" alt="Applist Detector">
  <img src="https://github.com/DawnyFY/lkm-susfs-manager/releases/download/v1.1.6/shot-ruru.png" width="250" alt="Ruru">
</p>

**未验证**：其余 7 个 KMI 仅有上游编译产物；官方 KernelSU / ReSukiSU / KernelSU Next 未实机测试（代码层面已兼容）。

## 构建

```sh
python tools/build_module_zip.py            # 打包 dist/susfs_allinone-<version>.zip
python tools/check_zip.py                   # 结构与内容校验
python tools/check_license_compliance.py    # 第三方许可门禁
```

构建使用固定时间戳与权限位，**同源码两次构建产物字节一致**（v1.1.6 起），便于第三方核对二进制与源码的对应关系。

CI 在每次 push / PR 时自动执行上述三项校验。

## 常见问题

<details>
<summary><b>模块装了但状态显示“未加载”</b></summary>

先看模块 `load.log`。常见原因：KMI 不在支持列表（日志会写“没有匹配 … 的 LKM”）、`.ko` 与内核不兼容、或当前环境没有可用的 root 会话。可先执行一次模块 Action 手动加载验证。
</details>

<details>
<summary><b>临时 root 设备：重启后模块不自动加载</b></summary>

late-load 模式下内核 `post-fs-data` 会被跳过，本模块已改为在 `boot-completed` 阶段兜底加载。若仍失败，请确认 SukiSU 已完成 late-load 注入（logcat 中应能看到 `late load mode`），再手动执行 Action。
</details>

<details>
<summary><b>规则写了但检测器仍能发现</b></summary>

先确认 `/proc/susfs_path` 中规则数量符合预期，再看 `hide_modules` 是否生效。注意 Zygisk 类模块必须在 **hot reboot 之后**才注入 zygote，冷启动后直接跑检测会得到误报。
</details>

<details>
<summary><b>会不会覆盖管理器自带的 ksu_susfs</b></summary>

不会。优先使用管理器自带的二进制，仅在它无法与内核通信时才回退到模块内置备份，且不覆盖原文件。
</details>

## 与上游功能的差异

上游模块的 WebUI 有十余个隐藏开关，本模块**只移植了在 late-load（临时 root）环境下不会出问题的那部分**。

### 已支持

| 开关 | 实现方式 |
|---|---|
| sus_path / sus_mount / try_umount | 规则文件逐条下发 |
| hide_modules / hide_sus_mnts | `/proc/susfs_hide_modules`、`ksu_susfs` |
| AVC 日志伪装 | `enable_avc_log_spoofing` |
| 隐藏 KSU LOOP 挂载 | 扫描 `/proc/mounts` 中 `/data/adb` 下的 loop 挂载，逐个 `add_sus_path_loop` |
| 隐藏 REVANCED / YouTube | 扫描 `*/revanced*`、`*/youtube*`、`*/microg*` 模块目录 |
| 隐藏自定义 ROM 路径 | 扫描 lineage / evolution / pixel / derpfest 等实际存在目录 |
| 隐藏 COMPAT MATRIX | 扫描 `*/etc/compat_matrix*` |
| 伪装 CMDLINE | `set_cmdline_or_bootconfig` |

### 刻意不移植

| 开关 | 原因 |
|---|---|
| 模拟 VOLD 应用数据隔离 | 依赖 vold 在**开机早期**完成 app data 挂载。late-load 时该阶段早已结束，设置上去要么无效、要么与已挂载状态冲突 |
| 隐藏 VENDOR SEPOLICY | init 与 selinux 在早期读取该文件，late 隐藏只对之后的读取者生效，可能让某些进程读不到而报错 |

> 这两项如果确实需要，请使用上游模块 + 永久 root（已解锁 BL）环境。

## 与上游项目的关系

本项目**不包含任何自研内核代码**。全部 SUSFS 能力来自以下上游项目，本仓库只做集成与适配：

```
├─ simonpunk / susfs4ksu        原始 SUSFS 内核补丁（GPL-2.0）
│    └─ inforcqb / susfs4ksu-lkm    SUSFS 的 LKM 移植，产出 8 个 KMI 的 .ko + susfs_insmod
│         ├─ 上游自带 loader        susfs_guard_lkm-module-<tag>-arm64.zip（只加载，无规则）
│         └─ 本项目  ← 在本仓库     加载 + 规则下发 + WebUI + late-load 适配
└─ sidex15 / ksu_module_susfs    ksu_susfs 用户态工具（AGPL-3.0）
```

| 上游 | 仓库 | 版本 | 本项目使用方式 |
|---|---|---|---|
| inforcqb / susfs4ksu-lkm | https://github.com/inforcqb/susfs4ksu-lkm | `v2.3.0-r18.4` | `lib/susfs_guard_lkm-*.ko`(8)、`bin/susfs_insmod`，**原样使用，哈希一致** |
| sidex15 / ksu_module_susfs | https://github.com/sidex15/ksu_module_susfs | `v1.5.2-R28` | `bin/ksu_susfs_good`（回退用），**原样使用** |
| simonpunk / susfs4ksu | 原始 SUSFS 项目 | — | 经 inforcqb 移植，本项目不直接引用 |

### 上游自带的 loader 模块

inforcqb 的 Release 里除了 `.ko`，还提供一个官方打包的模块 `susfs_guard_lkm-module-v2.3.0-r18.4-arm64.zip`。
它的定位（上游 module.prop 原文）：

```
description=not loaded yet - loads the matching .ko on boot
            (8 arm64 KMIs, 5.10-6.18). Loader only, no rules.
```

- **只负责加载**：`load.sh` 选 KMI → `susfs_insmod` → 写日志与 module.prop 描述，**不写任何 susfs 规则**
- 依赖 `post-fs-data.sh` 这个阶段（可选 `early_load` 提前到 `post-fs-data.d`）
- 没有 WebUI，没有规则管理，没有二进制回退

### 本项目的增量

| 能力 | 上游 loader | 本项目 |
|---|---|---|
| 按 KMI 加载 LKM | 有 | 有 |
| 规则下发（sus_path/sus_mount/try_umount/hide_modules） | 无 | **有** |
| **late-load（临时 root）适配** | 无（依赖 post-fs-data） | **有**（boot-completed 兜底） |
| WebUI | 无 | **有** |
| 分支兼容（SukiSU/ReSukiSU/Next/APatch） | 部分 | **有** |
| ksu_susfs 二进制回退 | 无 | **有** |
| 加载自限时 / 半加载保护 | 无 | **有** |
| 配置导入（旧 susfs4ksu） | 无 | **有** |

> 若你只需要“把 .ko 载进内核”，直接用上游官方模块即可。本项目的价值在于**加载之后的规则管理**与**临时 root 场景的适配**。

## 反馈与支持

### 提交前请先确认

1. 读过 [README](#lkm-susfs管理器) 与 [免责声明](#免责声明)
2. 你的问题**不是**以下已知情况：
   - 临时 root 重启后需要重新注入（环境限制，非缺陷）
   - 冷启动后 Zygisk 未注入导致检测器报异常（需要在 hot reboot 后再测）
   - KMI 不在支持列表（见「支持的 KMI」）
3. 手上已有 `load.log` 与 `apply.log`

### 选择正确的反馈渠道

| 情况 | 去哪 |
|---|---|
| 模块加载失败、规则没生效、WebUI 报错 | [提交问题](https://github.com/DawnyFY/lkm-susfs-manager/issues/new?template=bug_report.yml) |
| 希望增加功能 / 改进交互 | [功能建议](https://github.com/DawnyFY/lkm-susfs-manager/issues/new?template=feature_request.yml) |
| 使用经验、配置分享、闲聊 | [Discussions](https://github.com/DawnyFY/lkm-susfs-manager/discussions) |
| **内核模块崩溃 / `.ko` 兼容性问题** | 上游 [inforcqb/susfs4ksu-lkm](https://github.com/inforcqb/susfs4ksu-lkm/issues) |
| **`ksu_susfs` 二进制行为问题** | 上游 [sidex15/ksu_module_susfs](https://github.com/sidex15/ksu_module_susfs/issues) |
| 安全漏洞 | 见 [`SECURITY.md`](SECURITY.md)，**请勿公开开 issue** |

### 提交问题时的最小信息

缺少这些信息的问题基本无法定位：

```
设备型号：
Android 版本 / 内核版本（uname -r）：
管理器与版本：
root 类型：临时（未解锁 BL）/ 永久（已解锁 BL）
模块版本：
现象：
load.log / apply.log 内容（可附件）
```

> 建议直接使用 [问题模板](https://github.com/DawnyFY/lkm-susfs-manager/issues/new?template=bug_report.yml)，会引导你填完上述内容。

## 致谢

- **simonpunk** — SUSFS 原作者
- **inforcqb** — [susfs4ksu-lkm](https://github.com/inforcqb/susfs4ksu-lkm)，SUSFS 的 LKM 移植
- **sidex15** — [ksu_module_susfs](https://github.com/sidex15/ksu_module_susfs)，`ksu_susfs` 实现
- **SukiSU Ultra 团队** — 管理器与 late-load 机制

## 许可证

- 本项目的脚本、安装器与 WebUI：**GPL-2.0**（`LICENSE`）
- 随附第三方二进制（详见 `NOTICE`、`provenance.json`）：
  - `lib/susfs_guard_lkm-*.ko`、`bin/susfs_insmod` — inforcqb / `susfs4ksu-lkm` `v2.3.0-r18.4`，**GPL-2.0**，未修改
  - `bin/ksu_susfs_good` — sidex15 & simonpunk / `ksu_module_susfs` `v1.5.2-R28`，**AGPL-3.0**（`LICENSE-AGPL-3.0`），未修改
- 本仓库为上述组件的**聚合分发**，各组件版权与许可证归原作者所有
- 对应源码见 `NOTICE`；若无法获取，可向发布者索取（自发布之日起 3 年有效）

## 免责声明

**请在使用前完整阅读本节。安装或使用本项目，即表示你已理解并接受以下全部内容。**

### 1. 风险自担

本项目按 **“现状”（AS IS）** 提供，不作任何明示或默示担保，包括但不限于适销性、特定用途适用性与不侵权担保。
作者不对因使用或无法使用本项目造成的任何直接、间接、附带、特殊或后果性损害负责，包括但不限于：

- 设备无法开机（bootloop）、变砖、需要重刷系统
- 数据丢失或损坏
- 保修失效、系统稳定性下降、耗电异常
- 检测应用仍能识别环境（本项目**不保证**能通过任何检测）
- 触发厂商风控、账号受限

### 2. 适用环境有限

- **仅在以下环境实测**：Xiaomi 15 Ultra（25019PNF3C）/ Android 16 / 内核 6.6.77（`android15-6.6`）/ SukiSU Ultra 4.2.1 / bootloader 未解锁的临时 root。
- 其余 7 个 KMI 的 `.ko` 为上游编译产物，**本作者未实机验证**。
- 官方 KernelSU / ReSukiSU / KernelSU Next **未实机测试**，代码层面做了兼容但无法保证。
- 其他机型、其他内核版本、其他管理器组合，均属**未验证**范围。

### 3. 与 root / 解锁无关

本项目**不包含、不提供、不教授**任何 root 获取方式，也不涉及 bootloader 解锁、漏洞利用、漏洞编号、注入步骤或工具。

- 你需要**自行**拥有可加载内核模块的 root 环境；
- 对于未解锁 BL 的临时 root 环境，root 的获取与每次重启后的恢复由你自行负责；
- 本项目只做一件事：在**已经拥有 root 的前提下**，把 SUSFS 的 LKM 加载与规则下发自动化。

### 4. 明确禁止的操作

以下操作可能直接导致设备损坏且**难以恢复**，本项目明确不建议，作者不承担任何后果：

- 执行 `rmmod susfs_guard_lkm`（上游明确标注 UAF / panic 风险，可能当场崩溃）
- 为“修复模块”而解锁 bootloader、走 EDL / 9008、刷写 boot / init_boot
- 在生产机、主力机、唯一设备上首次尝试
- 在未备份、不了解恢复流程的情况下安装

### 5. 合规与使用场景

- 本项目面向**已获得设备所有权与操作权限**的用户，用于系统定制、隐私保护与安全研究。
- 请遵守你所在地区的法律法规与设备厂商的服务条款。
- **不得**用于侵犯他人设备、规避他人设备安全机制或任何未经授权的场景。
- 若你将本模块用于商业分发或集成到自有产品，需自行完成法律与合规审查。

### 6. 第三方组件与本项目无关

`lib/*.ko`、`bin/susfs_insmod`、`bin/ksu_susfs_good` 均来自上游项目（见“与上游项目的关系”与 `NOTICE`），
其正确性、安全性与行为由**原作者**负责。本作者仅按原样集成，未做修改，也不对其缺陷承担责任。

### 7. 无支持承诺

- Issue 与讨论区是**尽力而为**，不构成任何服务水平承诺。
- 缺少日志（`load.log` / `apply.log`）、缺少环境信息的反馈可能无法得到回复。
- 作者可随时停止维护、变更功能或删除仓库，无需事先通知。

### 8. 许可证优先

若本节内容与 `LICENSE`（GPL-2.0）存在冲突，以 **`LICENSE` 的法律条款为准**；本节仅为风险提示与使用建议。

---

**如果你不完全理解上述风险，请不要安装。**


## 内核匹配失败怎么办

模块按内核版本字符串里的 -androidXX-<kver> 标记选择 .ko。以下情况无法自动匹配：

- 内核字符串没有 Android 标记（常见于厂商自改内核，如 5.15.178-gxxx-dirty）
- 版本号对应多个 KMI（5.10 / 5.15 各有两个候选）

### 1. 先看诊断

su -c "sh /data/adb/modules/susfs_allinone/ctl.sh kmiinfo"

输出包含 osrelease、matched、packaged、guessed，以及 CONFIG_LOCALVERSION / CONFIG_MODVERSIONS / CONFIG_CFI_CLANG。

### 2. 手动指定 KMI

即使自动匹配失败，模块也会照常安装。在 WebUI 配置页填写「强制指定 KMI」，例如 android14-5.15，保存后点「加载并应用」。

### 3. 判断能不能用

- 官方 GKI（字符串带 -androidXX-）：用对应 KMI，成功率较高
- 自编译内核（带 -dirty）：很可能因符号或 CFI 不匹配加载失败，不要反复尝试

## 伪装内核版本（uname spoof）

WebUI「配置」页可开启 uname 伪装，只影响**用户态看到的内核版本**（`uname -r`、`/proc/version`），不影响 `.ko` 加载校验，也不能用来跨版本加载模块。

### 开机先记录真实内核

`load.sh` 在加载 LKM 时（任何伪装生效之前）会把真实值写入：

```
/data/adb/modules/susfs_allinone/state/real_uname.txt
```

```
release=6.6.77-android15-8-gca30f3b4bef6-abogki440974771-4k
version=#1 SMP PREEMPT Mon Sep  1 06:06:55 UTC 2025
saved_at=2026-10-24 00:19:24
```

只写一次；只有在「关闭伪装并成功还原」后才强制刷新，所以内核升级后会自动更新，也不会把伪装值误记成真实值。

### 出问题时的救援

```
su -c "sh /data/adb/modules/susfs_allinone/ctl.sh restore_uname"
```

直接读取快照并还原，**不需要重启**。

排查时用 `kmiinfo` 可同时看到当前值与快照值：

```
su -c "sh /data/adb/modules/susfs_allinone/ctl.sh kmiinfo"
```

输出末尾的 `--- real ---` 段就是开机时的真实内核。

### 与其他模块冲突时

若有别的模块强制加载全部模块、或手动 `insmod` 了不匹配的 `.ko` 导致异常：

1. 先看 `real_uname.txt` 确认真实内核版本
2. 用 `restore_uname` 撤销伪装
3. 仍不稳定则在管理器中禁用本模块后重启

> 快照文件位于 `/data/adb`，重启与模块禁用都不会删除。
