# 安装与卸载

## 要求

- **arm64** 设备；
- 受支持的 root 管理器：KernelSU 系 / Magisk / APatch（实验性）；
- 内核 KMI 在 [KMI 表](KMI.md) 内，或用 `force_kmi` 指定；
- 能加载内核模块的 root 环境；临时 root 需自行确认注入流程；
- APatch 额外要求：内核由 KernelPatch/kpimg 接管、允许加载 LKM；真实设备请先接受“未验收”风险。

## 安装前

- 备份当前可用的模块 zip 与 `config/`、`state/`；
- 确认 KMI（`ctl.sh kmiinfo` 或 WebUI 配置页）；
- 不要在已有 SUSFS LKM 运行的情况下重复加载。

## KernelSU 系列

适用于官方 KernelSU / SukiSU / ReSukiSU / BakaSU / KernelSU Next。

1. Release 下载 `susfs_allinone-<version>.zip`；
2. 管理器「模块 → 从本地安装」；
3. 重启，或执行模块 Action 手动加载；
4. 打开 WebUI 查看状态与规则。

开机阶段：`post-fs-data` → `boot-completed`。临时 root 的 late-load 场景由 `boot-completed` 兜底。

## Magisk

1. Magisk 管理器「模块 → 从本地安装」；
2. 重启（规则在 `service` late_start 阶段应用）；
3. 打开 WebUI 确认 LKM 与规则状态。

> Magisk 只做了代码路径适配，**未做真机冷启动验证**；首次使用请保留旧模块与恢复手段。

## APatch

1. 用 APatch 可用的模块安装方式安装本 zip（**APatch Manager 安装流程未实机验证**）；
2. 重启后默认**不会**自动外挂 SUSFS LKM；内核已内置 SUSFS 时无需放行；
3. 只有内核没有内置 SUSFS、且你接受风险时，才执行：
   ```sh
   su -c "sh /data/adb/modules/susfs_allinone/ctl.sh allow_lkm"
   ```
   或使用 WebUI 状态页的 APatch 卡片「放行 LKM」；
4. 放行后手动执行 `load.sh manual` 或重启验证。

详细范围、风险和未验证项见 [APatch 实验性支持](APATCH.md)。

## 升级

直接覆盖安装新 zip，`config/`、`state/` 会保留；升级后建议重新执行一次「仅应用配置」并检查 `ctl.sh status`。

## 回滚

- 恢复上一版本 zip 覆盖安装；
- 若版本间配置格式变化，模块会尝试迁移；仍异常时用备份恢复 `config/`；
- 不要在异常状态执行 `rmmod`；禁用模块后重启更安全。

## 安装后检查

```sh
su -c "sh /data/adb/modules/susfs_allinone/ctl.sh status"
```

重点看：

- `module_version`、`integrity`
- `lkm_present`、`lkm_version`
- `rules`、`apply_result`
- `kernelpatch_kernel`（APatch 环境）
- `load.log` / `apply.log`
