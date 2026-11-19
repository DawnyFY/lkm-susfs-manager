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

- 35/35 测试通过；1.2.5 的 kallsyms 零地址回退已验证（1.2.4/r18.9 冷启动已验证）。
- `check_zip` / `check_no_crlf` 通过。

## 1.2.8（2026-11-19）

构建：13,190,738 B，sha256 `ca1fca98b1c497194eea94ce6bd2770f43f532cc9eea2bd4804b7c032d15509f`，manifest `c3487cdb…`。
离线 35/35、门禁 5/5、`I18N_OK`。

- 界面：两套主题（`style.css` 冷蓝 `#2b7cff`/22px 圆角、`style-alt.css` 暖灰 `#4f46e5`/18px 圆角），关于页「主题 / Theme」切换，写 localStorage；页头图标已移除
- 实测：两套 CSS 变量探针分别为 `accent=#2b7cff bg=#f2f4f8` 与 `accent=#4f46e5 bg=#f3f3f0`；设备安装后 `webroot/` 两套 CSS 齐全、`brand-icon` 计数 0、`themeWarm` 存在、`integrity=ok`
- 上报：`kernel_version` 改为取 `/proc/version` 的构建 banner（此前与 `kernel_release` 重复）；服务端落库 `kernel_release` / `kernel_version`
- 服务端版本白名单：19/1.2.7 与 20/1.2.8 同时接受（实测两版均返回 token）
- 前端：Vite+Vue+TS 构建产物 166 KB（app.js 99.7 KB/gzip 36.9 KB）；Vitest 25/25；离线套件 36/36；门禁 5/5；产物指纹与源码一致（改源码后门禁会失败，已做反证）；设备侧 webroot 5 个文件齐全、index.html 引用全部可解析
- 未验证：其余 5 套 KMI；冷启动首次装载；真机 WebView 内的 Vue 运行时（需人眼确认一次）

## 1.2.7（已发布，2026-11-18）

构建：13,183,411 B，sha256 `574a466357ff698d2cbee635fa3ffa08330b12837dadc0d6cd949cd24099dd5e`，
manifest `8d93ac3c…`；同源码重建字节一致。离线 35/35、门禁 5/5、`I18N_OK`。

**Probe PID Guard（自研内核模块，Beta）**

- 装载：`ctl.sh pid_guard_reload` → `loaded=1`、`visible=0`、`hidden=1`、`result=ok`、`kmi=android15-6.6`
- 隐藏：`/proc/modules` 命中 0；`/proc/susfs_hide_modules` 名字含 `generic_pid_guard`
- sysfs：`parameters/` 三个文件 `-r--r-----`（0440）；`su 2000` 读 0400 对照文件为 Permission denied，参数文件对该 uid 不可见
- 参数即时生效：改 `target_uids` 后 `/sys/module/generic_pid_guard/parameters/target_uids` 立即变化
- 关闭：`enabled=0` → `result=unloaded`、`/sys/module` 消失、隐藏名单回到 `susfs_guard_lkm kernelsu`；改回 → 恢复
- 配置校验：`target_comms=*` / `target_comms=$(reboot)` / `target_uids=abc` / 两侧全空 → 全部 `rejected`，旧配置哈希不变
- 未验证：其余 5 套 KMI（只编译）；冷启动首次装载（临时 root 重启即失效）

**sus_path 目录重建**

- 首次 apply → 规则带真实 inode；不改动再 apply → `[=] 已存在`（无 churn）；
  删除重建后再 apply → `[i] inode 已变，撤销旧规则后重加` + 新 inode 落表
- 前提：`replace_rules=0` 才会走到该分支；`=1` 时每次全量重建，同样能恢复

**匿名统计**

- 开关在「关于」页，切换即写 `config.ini` 并生效；关闭立即删除 `state/server_token`
- 设备实测：`set_stats 0` → 值 0 且 token 删除；`set_stats 1` → 值 1、token 重签、`stats.log` 记 `reported version_code=19`
- 失败上报：`state/failures` 落盘（700/600），`/sdcard/Download` 不新增；`{"ok":true}` 返回正常
- 服务端只接受 1.2.7 / 19；1.2.6 请求返回 400

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
