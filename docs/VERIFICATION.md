# 验证记录与已知限制

## 环境

- Xiaomi 15 Ultra（25019PNF3C）
- Android 16 / kernel 6.6.77（`android15-6.6`）
- SukiSU Ultra 4.3.0 / bootloader 未解锁，临时 root

## 真机（KSU 系）

| 项目 | 结果 |
|---|---|
| 1.2.3 冷启动 | LKM 加载；`/proc/susfs_*` 9 个；`integrity=ok`；规则 11 |
| 1.2.3 热重启 | LKM / 规则 / 探测 / integrity 仍正常 |
| 1.2.4 冷启动（r18.9） | 加载 3,101,664 B / 116 symbols；LKM/规则/integrity 正常；LSPosed connected |
| LSPosed | 冷启动未 connected（临时 root / Zygisk 时序）；热重启后 connected、14 modules |
| APatch 卡片 | KSU 环境正确隐藏 |
| 1.2.3-dev 热回归 | `ctl.sh apply` rc=0、`apply_fails=0`，配置未丢 |

## QEMU GKI

- kpimg + SUSFS LKM：加载、隐藏、`add/del` 恢复；
- 模块级 APatch 路径（模拟 `/data/adb/ap`）：
  - 默认自动加载 → 跳过；
  - 手动加载 → 拒绝；
  - `allow_lkm` → 加载 → 规则生效；
  - 基线 / patched 各 14/14 断言。

## 离线

- 33/33 测试通过；1.2.5 的 kallsyms 零地址回退已验证（1.2.4/r18.9 冷启动已验证）。
- `check_zip` / `check_no_crlf` 通过。

## 1.2.6 候选（手动验证）

- 设备：Xiaomi 15 Ultra（8e483448），SukiSU，LKM r18.9，android15-6.6。
- 安装 1.2.6 后 `version=1.2.6` / `versionCode=18`，`lkm_present=1`、`rules=13`、`apply_result=success`、`integrity=ok`、`autoload=ok`。
- `sus_path_loop`：测试路径 apply 后在 `/proc/susfs_path` 出现；清空/恢复配置后测试规则消失；`export_log` 生成 `/sdcard/Download/susfs_allinone-log-*.txt` 且含 status/load/apply。
- `install_key`：`state/install_key` 65 B、`-rw-------`，`install_id` 为 16 位 hash；重复调用不重签。
- 未验证：真实 WebView 公告 fetch/CORS、Magisk/APatch 上的 set_perm 与 updateJson UI、所有 KMI 冷启动。

## 未验证

- 其余 7 个 KMI（只有上游 `.ko`）；
- Magisk 真机冷启动；
- APatch 真机全链路；
- 官方 KernelSU / ReSukiSU / BakaSU / KernelSU Next 实机；
- 长期稳定性、卸载/重载、升级路径。

## 已知限制

- **sus_path 持续隐藏缺口**：目标目录被删除重建后，旧 inode 规则失效；重新挂接原型（≤2s 窗口）未合并。
- **APatch 实验性**：真机未验收；APatch Manager 安装、真实 ABI/符号、WebUI 卡片交互未验证。
- **Magisk**：代码适配，未做真机冷启动验证。
- **dmesg 受限设备**：KernelPatch 探测可能显示 `unknown`，不影响加载策略。
- **默认隐藏 /data/adb**：`config/sus_path.txt` 默认包含 `/data/adb`；NeoZygisk v2.4 + r18.8 有外部反馈的 zygote 循环重启风险，使用 NeoZygisk 时必须删除该行；模块/SUSFS 不支持从已隐藏父目录排除子目录（本环境未复现）。
- **用户态取 LKM 状态**依赖管理器 `ksu_susfs` 或模块回退二进制；都不可用时只能看日志。
- 临时 root 每次重启都要重新注入，不是模块能修复的。
