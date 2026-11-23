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

- 各版本按发布时的脚本数统计（见下方分段）；1.2.5 的 kallsyms 零地址回退已验证（1.2.4/r18.9 冷启动已验证）。
- `check_zip` / `check_no_crlf` 通过。

## 1.3.0（待发布 · 2026-11-22）

构建：13,207,249 B，sha256 `3f8e3e3f2ced8d6312cc4dff3bb87191cfe6d6b568be1b39a4620c70ed1fed4e`，manifest `fba63cdd…`。
离线 **52/52**、Vitest **56/56**、门禁 **6/6**、`I18N_OK keys=199`；两次构建字节一致。

- 首次配置向导（五步）与启动动画；`wizard.ts` 的 `buildWizardBundle()` 在规则未加载时抛错（audit B1）
- `state/.lock.mutex` 按 mtime/pid 回收（audit B2）；AVC 开启时记录原值、关闭仅在"当前确为伪装值"时还原（audit M1/R2-1）
- pstore 崩溃归属单次分类 + 递增窗口（512 KB → 4 MB → 全文件），解析不出触发行时标 `crash_evidence=unknown`（audit R2-2）
- `withBusy` 改用任务计数，并发时 busy 不提前复位（audit R2-3）
- 真机：`integrity=ok`、`rules=11`、AVC 参数按配置设置与还原、残留 mutex 自动回收

## 1.2.9（已发布 · 2026-11-20）

构建（= 发布资产，下载回验一致）：13,192,648 B，sha256 `b1a3fd4f60ffe934c23e6cb36151538f45c43a3a3197943157e5b3eda0faf618`，
manifest `0700c256…`；tag `v1.2.9`。
离线 **40/40**（tag 内脚本数）、门禁 **5/5**。

- `status`：同一 boot 内探测结果缓存（`state/.probe_cache`），7 个 pid_guard 字段与规则数统计改内建读取；
  设备交错 A/B 中位数 2.29 s → 1.29 s（最好 0.90 s），未达 0.5 s 目标，剩余为解释开销
- `set_bundle`：段格式 `<字节数>:<base64>`，截断 payload 实测被拒（`长度不符：期望 18，实际 6`），v1 仍兼容
- 缓存击穿：`index.html` 里的 `app.js?v=<内容 sha256 前 8 位>` / `app.css?v=…` 由 `vite.config.ts` 在构建时写入，
  内容不变则 URL 不变（构建仍可复现），内容一变 URL 必变 —— 避免 WebView 继续用旧 bundle
- 日志去重：设备实测一次 pid_guard 真实加载写入 `Loaded kernel module` **1 条**（来自 `ksud insmod`）+ `[i] pid_guard 已加载（KMI 6.6，参数已生效）` **1 条**，此前是同一句重复两次
- 时间戳：`now_stamp()` 在年份不可信时输出 `开机+Ns（RTC 未同步）`；`load.sh`/`apply.sh` 块头与 `pid_guard.status` 的 `ts=` 均已切换；`apply.log`/`load.log` 中不再新增 `1970-` 记录
- 卸载无操作不再写日志（`pid_guard 未加载，无需卸载` 只在实际卸载时才由 `[-]` 行体现），状态仍记 `skipped`
- 设备（Android 16 / 6.6.77 / SukiSU）：`module_version=1.2.9`、`integrity=ok`
- 其余与 1.2.8 相同（WebUI、主题、接口、PID Guard 默认关闭）

## 1.2.8（已发布 · 2026-11-19）

构建（= 发布资产，下载回验一致）：13,186,088 B，sha256 `0a7557cb85de3a4cb861df5197ceb43d14332bd40de6a714ad4a8b6136475258`，
manifest `97b570cd…`；tag `v1.2.8`。
离线 **37/37**（tag 内脚本数）、门禁 **5/5**。

**前端（Vite + Vue 3 + TS 重写）**

- 产物：`webroot/` 合计 175,650 B（`assets/app.js` 109,085 B、`assets/app.css` 11,714 B、`contributor.jpg` 54,062 B、
  `index.html`、`.build.json`）；打成 IIFE 经典脚本，产物内无 `type="module"` / `import` / `import.meta`
- 主题：`data-theme="cool|warm"` + CSS 变量两套；数值取自社区原版（cool 22/14、warm 18/10，按钮 999/11，开关 48×26 / 44×26）
- 布局：固定高度 + 内容区内部滚动，页签静态定位（无 `position: fixed` / `sticky` / `backdrop-filter`）
- 设置持久化：`localStorage` 存主题与语言；`?theme=cool|warm` 可临时预览且不落盘
- 设置保存：双层 base64 线格式（每段 b64 → `|` 连接 → 整体 b64），与 `ctl.sh set_bundle` 严格对应；
  三道防线（段数=8 / 非空段解出 0 字节 / 重编码一致）拦非法与半截编码；4 字节边界截断检测不到（见 BACKLOG ISS-008）；
  单层编码会被拒绝（`rejected: decode config.ini (空输出)`），不再出现 1.2.8 早期的「保存即清空配置」回归
- 无 `eval` / `new Function`；`v-html` 只绑定硬编码 SVG 图标；外链仅头像（失败回退首字母）与公告 JSON（6 s 超时、静默失败）

**PID 隐藏页与默认值**

- 出厂 `enabled=0`；`customize.sh` 仅在「旧配置与 1.2.7 出厂原样逐字节相同」时迁移，用户改过的不动
- 安装期临时文件（`.pid_guard.conf.new`、1.2.7 遗留 `pid_guard.conf.tmp.*`）在 `customize.sh` 末尾统一清理

**接口性能（设备实测，`time` 内建）**

| 命令 | 之前 | 现在 |
|---|---|---|
| 配置页数据 `get_bundle` | 8 次往返 | **0.18–0.29 s**（1 次） |
| PID 页数据 `pid_guard_bundle` | ~2.3 s（含完整 status） | **0.12–0.19 s**（1 次） |
| `ctl.sh status` | 2.06 s | 1.64–1.77 s（仍偏慢，见 `docs/BACKLOG.md` ISS-001） |

**未验证**

- 其余 5 套 KMI；冷启动首次装载（临时 root 重启即失效）
- 真机 WebView 内的极端窄屏（&lt;360px）与深色模式组合

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
