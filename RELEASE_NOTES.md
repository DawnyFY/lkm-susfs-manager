# LKM SUSFS管理器 v1.2.3

> 这是一个以 KernelSU 系列设备验证为主、APatch 仍标注为实验性的版本。APatch 真机未验收，默认不自动加载 SUSFS LKM。

## 重点变化

- **APatch 状态卡**：WebUI 状态页新增 APatch/KernelPatch 卡片，显示 APatch 用户态、KernelPatch 内核（含版本）、共存模式、SUSFS LKM 放行状态，并提供显式放行/取消放行按钮。
- **KernelPatch 内核运行时探测**：通过 dmesg 的 `KernelPatch Version:` banner 判断 kpimg 是否激活；dmesg 不可读时返回 `unknown`，不误报 0/1。
- **KMI 自动消歧**：无 Android tag 的 5.15 内核（如 `5.15.197-...-dirty`）可按 SDK 33/34 自动选择 `android13-5.15` / `android14-5.15`；仅当对应 KMI 已打包且 `.ko` 存在时采用，否则仍拒绝。
- **APatch 安全策略不变**：APatch/KernelPatch 下默认不自动外挂 LKM；手动加载必须 `ctl.sh allow_lkm` 或 WebUI 放行。
- **WebUI 状态语义**：ctl apply/load 的 rc=5 按“部分成功”提示并继续刷新；内核 builtin SUSFS 不再显示为 LKM，版本标签改为“内置 SUSFS”。
- **修复（审计 F1/F3）**：连续失败 3 次后的自动暂停不再被启动守卫清理；APatch 判定收紧为 `apd` 强特征，残留 `package_config` 不再误拦 LKM。

## 自 1.2.1 起的变更

- **1.2.2（未单独发布）**：英文界面（默认跟随系统语言）；Magisk 适配 `service` late_start 阶段应用规则。
- **1.2.3**：APatch WebUI 卡片、KernelPatch 运行时探测、dirty 5.15 KMI SDK 消歧、仓库目录重构（运行文件移入 `module/`）。

## APatch 支持状态（实验性）

- 已在 QEMU GKI（ImageG.orig / ImageG.patched，kpimg d09）验证：模块检测、默认拒绝、`allow_lkm` 放行、`load.sh` 加载、`apply.sh` 规则下发、隐藏/恢复，基线/patched 各 14/14 断言。
- 尚未在真实 APatch 设备验证：APatch Manager 安装、真实 `apd`/内核 ABI/符号、APatch 授权语义、开机阶段、WebUI 卡片视觉与按钮交互。
- 因此本版本**不宣称 APatch 已兼容**；只提供实验性路径，默认安全拒绝。

## 验证

- 离线测试：29/29 通过；`check_zip` / `check_no_crlf` 通过。
- QEMU GKI：kpimg + SUSFS LKM 加载/隐藏/删除恢复；模块级 APatch 路径 14/14。
- 真机（KSU/SukiSU，Android 16）：冷启动 LKM 加载、9 个 `/proc/susfs_*`、规则/完整性正常；热重启后 LSPosed 恢复 connected、模块仍正常。

## 已知限制

- **APatch 真机未验收**：默认不自动加载；放行属于实验性共存，可能与 kpimg 冲突导致启动异常。
- **sus_path 持续隐藏缺口**：目标目录被删除重建后，旧 inode 规则失效；重新挂接原型（≤2s 窗口）未合并。
- **Magisk**：本周期未做 Magisk 真机冷启动验证。
- **dmesg 受限设备**：KernelPatch 探测可能显示 `unknown`，不影响模块加载策略。
- **APatch WebUI**：卡片只在 APatch/KernelPatch 环境显示；未做真机视觉验证。
- **默认隐藏 `/data/adb`**：`config/sus_path.txt` 默认包含 `/data/adb`。NeoZygisk v2.4 + r18.8 在部分设备上可能因 `dlopen /data/adb/neozygisk/...` 被隐藏而触发 zygote 循环重启（外部反馈，本环境未复现）。**使用 NeoZygisk 时请删除该行，或至少排除 `/data/adb/neozygisk`**；详见 `docs/RELEASE_NOTES_122.md`。
- **APatch 判定**：只认运行态/可执行体（`pidof apd`、`/data/adb/apd`、`ap/bin/apd`）；残留 `package_config` 不再单独触发 APatch 保护，避免换过管理器的设备被误拦。

## 升级 / 回滚

- 升级：模块管理器安装本 zip；配置与规则保留在 `config/`、`state/`。
- 回滚：恢复上一版本模块 zip；本版本未改动 LKM ABI/配置格式。

## 校验

- 文件：`susfs_allinone-1.2.3.zip`
- 大小：11,066,555 B
- sha256：`b64b597a5c9d0fd9b7fa6f3128b052d7c2de2b5ba1b5338089d052f56f11b061`

## 说明

APatch/KernelPatch 共存问题欢迎附内核版本、kpimg/KernelPatch 版本、`ctl.sh status` 与 `load.log` 反馈；没有真机日志前，请勿把 APatch 路径用于生产设备。
