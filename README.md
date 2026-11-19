# LKM SUSFS管理器

<p align="center">
  <a href="README.en.md">English</a> · 中文<br>
  <b>KernelSU 系列 · Magisk · APatch（实验性）</b><br>
  <b>SUSFS LKM 自动匹配 / 加载 / 规则管理</b>
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

一个**多管理器**的 SUSFS LKM 管理器：自动匹配 KMI → 加载 SUSFS LKM → 下发规则 → 状态写回模块描述，附带中文/英文 MIUIX WebUI。

1.2.7 起除上游 SUSFS LKM 外，还自带一个**自研内核模块** Probe PID Guard（`generic_pid_guard`，GPL-2.0，源码在 `source/generic_pid_guard/`），按 UID/comm 伪装 `getppid`。

不再只适用于 KernelSU 系：

- **KernelSU 系列**：官方 KernelSU / SukiSU / ReSukiSU / BakaSU / KernelSU Next
- **Magisk**：按 late_start 阶段应用规则
- **APatch / KernelPatch**：实验性支持，默认拒绝外挂 LKM，需显式放行

> **实验性项目。** KSU 系已做真机冷/热启动验证；Magisk 仅代码适配；APatch 仅 QEMU 验证，**真机未验收**。刷机与 root 有风险，请自行评估恢复手段。

## 支持矩阵

| 管理器 | 适配 | 验证状态 | 开机阶段 |
|---|---|---|---|
| KernelSU 官方 / SukiSU / ReSukiSU / BakaSU / KernelSU Next | 完整 | SukiSU 实机冷/热启动验证；其余代码兼容，未逐一实机 | post-fs-data → boot-completed |
| Magisk | 完整 | 代码适配，未做真机冷启动 | post-fs-data → service |
| APatch / KernelPatch | **实验性** | 仅 QEMU GKI；真机未验收 | post-fs-data → boot-completed，默认拒绝 LKM |

## 快速开始

1. 从 [Releases](https://github.com/DawnyFY/lkm-susfs-manager/releases) 下载 `susfs_allinone-<version>.zip`；
2. 按管理器安装：
   - [KernelSU 系列安装](docs/INSTALL.md#kernelsu-系列)
   - [Magisk 安装](docs/INSTALL.md#magisk)
   - [APatch 安装（实验性）](docs/INSTALL.md#apatch)
3. 重启，或执行模块 Action 手动加载；
4. 打开 WebUI 查看状态与规则。

## 功能亮点

- **8 个 KMI 自动匹配**（android12-5.10 ～ android17-6.18）；无 Android tag 的 5.15 支持按 SDK 自动消歧。
- **多管理器开机阶段**：KSU 系 / APatch 走 `boot-completed`，Magisk 走 `service`；boot-completed 会检查 LKM 状态，未加载时补一次（不显式判断 late-load）。
- **APatch 检测与安全策略**：识别 `/data/adb/ap` / `apd`，默认不自动外挂 LKM，需显式放行。
- **KernelPatch 运行时探测**：读 dmesg banner；不可读显示 `unknown`，不误报。
- **启动守卫 / pstore 崩溃暂停 / 半加载保护**：避免错误 LKM 导致反复 bootloop。
- **规则与隐藏**：`sus_path`、`sus_mount`、`try_umount`、`hide_modules`、AVC 伪装、扩展隐藏项。
- **WebUI**：状态 / 配置 / PID 隐藏 / 日志 / 关于；APatch 环境额外显示 APatch 卡片。
- **两套主题**（1.2.8+）：冷蓝圆角（默认）/ 暖灰极简，在关于页切换，选择存本地。
- **前端技术栈**（1.2.8+）：Vite + Vue 3 + TypeScript 构建，Vitest 单测；产物打成 IIFE 经典脚本（不用 ESM），兼容 `ksu://` 加载方式；多语言改为 JSON 词典 + `template.json`，社区可直接提交翻译。
- **Probe PID Guard（Beta，可选）**：自研 `generic_pid_guard` LKM，`kretprobe __arm64_sys_getppid`，按 UID 范围 / comm 前缀伪装 `getppid`；随包 6 套 KMI（5.10/5.15/6.1/6.6/6.12/6.18），默认关闭、需要时在「PID 隐藏」页开启；装载后自动写入 `/proc/susfs_hide_modules`，与 `kernelsu` 同级隐藏。
- **「PID 隐藏」一级页**：六张状态卡（已启用 / 内核模块 / 内核可见 / 隐藏列表 / 最近结果 / 命中进程）+ 独立保存；改参数即时 `rmmod`+`insmod`，关闭立即卸载。

## APatch（实验性）

APatch/KernelPatch 下默认**不自动加载** SUSFS LKM；需要外挂时，先确认内核没有内置 SUSFS，再执行 `ctl.sh allow_lkm` 或 WebUI 放行。QEMU 已验证模块路径 14/14，但真机安装、ABI、WebUI 卡片均未验收。

详见 [APatch 实验性支持](docs/APATCH.md)。

## 自研内核模块（1.2.7+）

模块现在包含两个内核侧组件，来源不同，请分开看待：

| 组件 | 来源 | 许可证 | 说明 |
|---|---|---|---|
| `lib/susfs_guard_lkm-*.ko`、`bin/susfs_insmod` | 上游 inforcqb/susfs4ksu-lkm | GPL-2.0 | 未修改，sha256 与上游 Release 一致 |
| `lib/pid_guard/<kmi>/generic_pid_guard.ko` | **本项目自研** | GPL-2.0 | 源码随仓库分发：`source/generic_pid_guard/` |

Probe PID Guard 是本项目自行编写并编译的：`kretprobe __arm64_sys_getppid`，命中目标后改写返回值；
参数在 insmod 时传入（`target_uids` / `target_comms` / `exclude_comms`），
sysfs 侧权限为 `0440`，只有 root 可读。它是可选组件，1.2.8 起默认关闭；开启后开机自动加载，关闭即卸载。

```
source/generic_pid_guard/
├── generic_pid_guard.c     # 唯一源文件
├── generic_pid_guard.lds
├── Makefile
├── build_one.sh            # 在 DDK 容器里编单个 KMI
├── build_inside.sh
└── README.md               # KMI 表、编译命令、产物 sha256
```

## 构建前端

WebUI 源码在 `webui/`，构建产物落在 `module/webroot/`（已随仓库提交，用户不需要 node）：

```sh
sh tools/build_webui.sh          # npm ci（首次）+ 类型检查 + vite build + 写源码指纹
```

`module/webroot/.build.json` 记录源码指纹；`tools/check_zip.py` 会复算比对，
改了 `webui/src` 却忘记重建时门禁直接失败。

## 安全

- 不要重复加载 LKM，不要执行 `rmmod susfs_guard_lkm`；
- 不要同时启用两个会加载 SUSFS 的模块；
- APatch 放行可能导致 bootloop，只在测试设备尝试；
- 出问题先禁用模块并保留 `load.log` / `apply.log`。

完整安全与免责条款见 [安全与免责](docs/SAFETY.md)。

## 文档

| 文档 | 内容 |
|---|---|
| [安装与卸载](docs/INSTALL.md) | KSU / Magisk / APatch 安装、升级、回滚 |
| [APatch 实验性支持](docs/APATCH.md) | 已验证/未验证范围、放行步骤、风险 |
| [KMI 匹配](docs/KMI.md) | KMI 表、dirty 内核、强制指定、排错 |
| [配置与 WebUI](docs/CONFIG.md) | `config.ini`、规则文件、WebUI 页面 |
| [常见问题](docs/FAQ.md) | 加载失败、APatch 卡片、Magisk、Zygisk |
| [验证记录与限制](docs/VERIFICATION.md) | 真机/QEMU/离线记录、已知限制 |
| [安全与免责](docs/SAFETY.md) | 安全规则、禁止操作、免责声明 |
| [上游关系与许可](docs/UPSTREAM.md) | 第三方组件、版本、许可证、致谢 |
| [反馈与支持](docs/SUPPORT.md) | 反馈渠道、最小信息、日志要求 |

## 验证与限制（摘要）

- KSU 系：1.2.4 冷启动加载 r18.9（3,101,664 B / 116 symbols），规则/完整性正常；热重启后 LSPosed 保持 connected。
- QEMU GKI：SUSFS LKM 加载/隐藏/恢复；模块级 APatch 路径 14/14。
- 离线：35/35 测试通过。
- 未验证：Magisk 真机冷启动、APatch 真机全链路、其余 7 个 KMI。
- PID Guard：真机仅 6.6.77 验证装载 / 隐藏 / 参数即时重载 / 关闭卸载；其余 5 套 KMI 只编译未运行。
- `sus_path` 目录重建：1.2.7 起普通规则也按 inode 比对，下次 apply 会撤销旧规则并按新 inode 重加；即时恢复仍需内核事件钩子（原型未合并）。
- 默认隐藏 `/data/adb`：NeoZygisk 用户必须删除该行；模块/SUSFS 不支持从已隐藏父目录中排除子目录（外部反馈的 zygote 循环风险）。

详见 [验证记录与限制](docs/VERIFICATION.md)。

## 反馈

- Bug：[提交问题](https://github.com/DawnyFY/lkm-susfs-manager/issues/new?template=bug_report.yml)
- 功能建议：[Feature request](https://github.com/DawnyFY/lkm-susfs-manager/issues/new?template=feature_request.yml)
- 使用经验：[Discussions](https://github.com/DawnyFY/lkm-susfs-manager/discussions)
- 安全漏洞：见 `SECURITY.md`，请勿公开开 issue
- 上游 `.ko` / `ksu_susfs` 问题：优先找上游仓库

提交前请附 `load.log`、`apply.log`、`ctl.sh status`；APatch 反馈另附 KernelPatch 版本与 `allow_lkm` 状态。

## 许可证

- 本项目脚本/安装器/WebUI：**GPL-2.0**（`LICENSE`）
- 第三方二进制：`lib/susfs_guard_lkm-*.ko`、`bin/susfs_insmod`（GPL-2.0）、`bin/ksu_susfs_good`（AGPL-3.0）
- 自研内核模块：`lib/pid_guard/<kmi>/generic_pid_guard.ko`（GPL-2.0），源码 `source/generic_pid_guard/`
- 版权与许可证归原作者所有，详见 [上游关系与许可](docs/UPSTREAM.md)、`NOTICE`、`provenance.json`

---

**如果你不完全理解风险，请不要安装。**
