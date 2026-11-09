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

一个**多管理器**的 SUSFS LKM 模块：自动匹配 KMI → 加载 SUSFS LKM → 下发规则 → 状态写回模块描述，附带中文 MIUIX WebUI。

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
- **WebUI**：状态 / 配置 / 日志 / 关于；APatch 环境额外显示 APatch 卡片。

## APatch（实验性）

APatch/KernelPatch 下默认**不自动加载** SUSFS LKM；需要外挂时，先确认内核没有内置 SUSFS，再执行 `ctl.sh allow_lkm` 或 WebUI 放行。QEMU 已验证模块路径 14/14，但真机安装、ABI、WebUI 卡片均未验收。

详见 [APatch 实验性支持](docs/APATCH.md)。

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

- KSU 系：1.2.3 冷启动 LKM/规则/完整性正常；热重启后 LSPosed 恢复。
- QEMU GKI：SUSFS LKM 加载/隐藏/恢复；模块级 APatch 路径 14/14。
- 离线：29/29 测试通过。
- 未验证：Magisk 真机冷启动、APatch 真机全链路、其余 7 个 KMI。
- 已知缺口：`sus_path` 目标目录删除重建后旧 inode 规则失效（重新挂接原型未合并）。
- 默认隐藏 `/data/adb`：NeoZygisk 用户需删除该行或排除 `/data/adb/neozygisk`（外部反馈的 zygote 循环风险）。

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
- 版权与许可证归原作者所有，详见 [上游关系与许可](docs/UPSTREAM.md)、`NOTICE`、`provenance.json`

---

**如果你不完全理解风险，请不要安装。**
