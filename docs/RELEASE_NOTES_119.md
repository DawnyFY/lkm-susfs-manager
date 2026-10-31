## 1.1.9

### 新增
- **启动守卫（防重启循环）**：自动加载前落标记，只有真正跑完 `boot-completed` 才清除。若加载错 `.ko` 导致 panic，下次开机会检测到标记残留并**自动暂停加载**，系统正常进入桌面；修好 KMI 后点「加载并应用」即可恢复。覆盖 `post-fs-data` 与 late-load 两条路径。
- **BL 解锁检测**：读取 `ro.boot.verifiedbootstate` / `ro.boot.flash.locked` / `ro.secureboot.lockstate`，`ctl.sh status` 输出 `bootloader=locked|unlocked|unknown`。
- **仅解锁 BL 可用**：隐藏 VENDOR SEPOLICY、模拟 VOLD 应用数据隔离。未解锁设备在 WebUI 里**整组隐藏**（可执行 `ctl.sh preset_paths` 验证不存在）。
- **新增隐藏开关**：隐藏 GAPPS、强制隐藏 DEX2OAT 挂载、隐藏 Scene 痕迹（`/dev` 下随机命名的目录，含 `scene_mode_category` 时按内容识别，不依赖固定名字）。
- **预设隐藏项弹窗**：配置页「开关」右侧按钮，按设备真实存在的目录列出候选（KSU / APatch / Magisk 目录、`post-fs-data.d`、`service.d`、`susfs4ksu`、`/dev` 下 Scene 痕迹、常见调整工具遗留文件），带三态全选与 `已选/总数` 计数。
- **BakaSU 识别**：与 ReSukiSU 包名相同（`com.resukisu.resukisu`），显示为「ReSukiSU / BakaSU」；可用配置项 `manager_name=BakaSU` 精确显示。

### 修复
- 修复 1.1.9 首版 WebUI 保存失败：`managerName is not defined`（变量作用域错误，#1）。
- 回退资源 `?v=` 查询串，避免 `file://` 加载时资源失败。
- 弹窗打开时背景仍可滚动、触摸锁选择器写错（`.container` → `.app`）。
- 预设弹窗复选框全部被禁用导致无法勾选。
- 全选改为标准三态逻辑，仅作用于已发现项，未发现项可单独勾选。
- 预设列表不再过滤已配置项，改为标注「已在列表」。
- 弹窗资源加 `?v=` 版本号，升级后强制重载，避免 WebView 缓存旧 JS。
- `presetModal` 曾被写在 `</html>` 之外，已移回 `<body>` 内。

### 清理
- 删除死代码：`read_entries()`、未使用的 `.row-actions` 样式、`load.sh` 中重复的 `save_real_uname` 调用、无对应规则的 `hidden-group` 类名。
- `post-fs-data.sh` 与 `boot-completed.sh` 重复的门禁判断合并为 `common.sh` 的 `boot_gate_ok`。

### 验证
- 冷启动（无 root）：模块零执行，`verifiedbootstate=green`。
- 注入临时 root：自动加载，`init_module(2489936 bytes, 102 symbols absolutized)`。
- 热重启：状态保持，`fail_count=0`。
- 设备：Xiaomi 15 Ultra / Android 16 / 6.6.77-android15-6.6 / SukiSU。

### 已知限制
- 启动守卫的 panic 场景未端到端复现（需真实内核崩溃），已验证标记判定与暂停/恢复逻辑。
- 本 LKM 未启用 `HIDE_SUS_MNTS`、`AVC_LOG_SPOOFING`、`SUS_PATH_LOOP`，对应开关会明确跳过。
- 仅解锁 BL 的两项在临时 root 下不显示，原因是开机早期阶段已过。