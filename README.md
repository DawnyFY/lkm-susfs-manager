# LKM SUSFS管理器

面向 KernelSU 系列（KernelSU / SukiSU / ReSukiSU / KernelSU Next）的 SUSFS LKM 自动匹配、加载与规则管理模块，含中文 MIUIX WebUI。

> **实验性项目。** 当前仅在 Xiaomi 15 Ultra、Android 16、kernel 6.6.77、SukiSU Ultra 临时 root、锁定 bootloader 环境验证。刷机/root 有风险；请先备份并理解你的设备恢复流程。

## 功能

- 8 个 KMI 自动匹配（android12-5.10 到 android17-6.18）。
- 开机早期加载 SUSFS LKM，开机完成应用规则。
- `ksu_susfs` 多路径发现；优先当前管理器/分支二进制，失败回退模块备份，不覆盖分支文件。
- 规则：`sus_path`、`sus_mount`、`try_umount`、`hide_modules`、`hide_sus_mnts`、AVC spoof 开关。
- 中文 MIUIX WebUI：状态 / 配置 / 日志 / 关于；浅色/深色；无外部 CDN。
- 升级保留配置；首次安装可导入旧 `susfs4ksu` 配置。
- 模块 Action：手动加载/应用，不依赖开机自启动。

## 要求

- arm64。
- KernelSU 系列管理器（官方 KernelSU / SukiSU / ReSukiSU / KernelSU Next）。
- 内核 KMI 在打包列表内。
- 需要能加载 LKM 的 root 环境；锁定 bootloader 的临时 root 方案需自行确认可用性。

## 安装

1. 从 Release 下载 `susfs_allinone-<version>.zip`。
2. 在 KernelSU 管理器中安装。
3. 重启后按你的 root 流程验证；或在模块 Action 中手动加载。
4. 打开模块 WebUI 查看状态/配置。

## 配置

`config/config.sh`：

```sh
auto_load=1
hide_sus_mnts=1
avc_spoof=0
replace_rules=1
```

- `replace_rules=1`：应用前清空未列出的普通 `sus_path` 规则；如果还有其他工具写规则，改为 0。
- `sus_path.txt`：每行一个路径，支持注释。
- `hide_modules.txt`：每行一个模块名，默认 `kernelsu`。

升级时保留现有配置；首次安装才尝试导入 `/data/adb/susfs4ksu`。

## 安全

- **不要执行 `rmmod susfs_guard_lkm`**（已知 UAF/panic 风险）。
- 不要解锁 bootloader / EDL / 刷 boot 来“修复”模块。
- 锁定 bootloader + 临时 root 的用户：每次重启后需要重新走 root 流程。
- 出问题先在管理器中禁用模块或执行 Action；保留旧模块作为回退。
- 本项目不提供解锁/刷机/绕过安全机制的教程。

## 测试边界

- 已测试：SukiSU Ultra、Xiaomi 15 Ultra、android15-6.6 的 LKM 加载与 8 条规则。
- 尚未验证：真正冷启动自动链路、停用旧模块后的复测、Wild Detector 实验检测、其他分支/其他 KMI 的实机。
- 不要把“当前 LKM 已加载”当作“自动加载已验证”。

## 构建

```sh
python tools/build_module_zip.py
python tools/check_zip.py
```

输出 `dist/susfs_allinone-<version>.zip`。

## 致谢 / License

- SUSFS LKM：`inforcqb/susfs4ksu-lkm`，`v2.3.0-r18.4`，arm64，8 个 KMI；见 `provenance.json`。
- 旧模块/参考：`susfs4ksu`、`susfs_oneshot`。
- 许可证见 `LICENSE`；第三方二进制/来源以其原许可证为准。

## 免责声明

本项目按“现状”提供，不保证适用于所有设备/内核/管理器。使用导致的数据丢失、无法开机、检测失败等风险由使用者承担。

## License / 许可证

- 本项目的 shell 脚本、安装器与 WebUI：**GNU GPL v2.0**（`LICENSE`）。
- 随附第三方二进制（详见 `NOTICE` 与 `provenance.json`）：
  - `lib/susfs_guard_lkm-*.ko`、`bin/susfs_insmod` — inforcqb / `susfs4ksu-lkm` `v2.3.0-r18.4`，**GPL-2.0**（未修改，哈希与上游 Release 一致）；
  - `bin/ksu_susfs_good` — sidex15 & simonpunk / `ksu_module_susfs` `v1.5.2-R28`，**AGPL-3.0**（`LICENSE-AGPL-3.0`，未修改）。
- 本仓库是上述 GPL-2.0 与 AGPL-3.0 组件的**聚合分发**，各组件的版权与许可证归原作者所有。
- 对应源码：见 `NOTICE` 中的仓库与 tag；若无法获取，可向发布者索取（自发布之日起 3 年有效）。
