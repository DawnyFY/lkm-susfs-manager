# APatch 实验性支持

> **结论先行：APatch 目前是实验性路径，真机未验收。** 没有 QEMU 之外的 APatch 真机日志前，不建议用于生产/主力设备。

## 适用范围

- 内核由 KernelPatch / kpimg 接管；
- 内核没有内置 SUSFS，需要外挂 SUSFS LKM；
- 你接受实验性共存风险，并有恢复手段。

## 检测特征

只认运行态或可执行体：`pidof apd`、`/data/adb/apd`、`/data/adb/ap/bin/apd`。只有残留的 `/data/adb/ap` 目录或 `package_config` 不会触发 APatch 保护，避免换过管理器的设备被误拦。

## 默认策略

- APatch/KernelPatch 下**不自动加载** SUSFS LKM；
- 手动加载也会被拒绝；
- 需要时显式放行：

```sh
su -c "sh /data/adb/modules/susfs_allinone/ctl.sh allow_lkm"
# 取消
su -c "sh /data/adb/modules/susfs_allinone/ctl.sh disallow_lkm"
```

或 WebUI 状态页 APatch 卡片「放行 LKM / 取消放行」。

- 放行标记是独立文件 `config/allow_lkm_on_kernelpatch`，不在 `config.ini` 里；
- 检测到上次启动有 SUSFS 相关 panic/oops（pstore）时，自动加载暂停；
- 检测到 KernelPatch 时自动关闭与之重叠的 `avc_spoof`。

## 已验证什么

- **QEMU GKI（6.6，kpimg d09）**：SUSFS LKM 可加载；规则隐藏/恢复可用。
- **模块级 APatch 路径（QEMU 模拟 `/data/adb/ap`）**：
  - 默认自动加载 → 跳过；
  - 手动加载 → 拒绝；
  - `ctl.sh allow_lkm` → 放行；
  - `load.sh manual` → 加载成功；
  - `apply.sh` → 规则生效；
  - 基线 / patched 各 14/14 断言通过。

## 未验证什么

- 真实 APatch Manager 安装流程、`apd` 用户态、APatch 授权语义；
- 真实 APatch 内核的 ABI / 符号 / CFI / KMI 差异；
- WebUI APatch 卡片在真机上的显示与按钮交互；
- 长期稳定性、卸载/重载、升级路径。

## 风险

- 放行属于实验性操作，**可能 bootloop**；只在测试设备尝试。
- 不要与内置 SUSFS 或其他 SUSFS LKM 模块叠加。
- 放行前备份，确认可以禁用模块或恢复系统。

## 反馈 APatch 问题

请附：

- 设备型号、Android / 内核版本；
- KernelPatch/kpimg 版本；
- `ctl.sh status` 完整输出；
- `kernelpatch_kernel` / `allow_lkm` 状态；
- `load.log`、`apply.log`；
- 是否内核已内置 SUSFS。
