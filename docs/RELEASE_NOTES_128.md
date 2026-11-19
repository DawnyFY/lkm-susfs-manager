# LKM SUSFS管理器 1.2.8

这一版主要是**界面**：两套主题，可在关于页切换；外加两处上报侧的收尾。

## 界面（重写）

前端整体迁移到 **Vite + Vue 3 + TypeScript**，行为与 1.2.7 对齐：

- 5 个页签：状态 / 配置 / PID 隐藏 / 日志 / 关于；支持 `#config` 这类深链
- 构建产物打成 **IIFE 经典脚本**（不是 ESM），兼容 KernelSU 用 `ksu://` 加载页面的老 WebView
- 多语言改为 JSON 词典（`zh-CN.json` / `en-US.json` / `template.json`），社区可直接提交翻译
- 主题用 `data-theme` + CSS 变量切换，不再需要两份完整样式表
- 体积 166 KB（`app.js` 99.7 KB / gzip 36.9 KB，`app.css` 6.3 KB），比 1.2.7 的 240 KB 更小
- 新增 `webui/tests/`（Vitest 25 个断言）覆盖 ini 文本改写、词典一致性、主题、ksu 桥接
- 门禁新增「产物与源码指纹一致」检查，改了前端忘记重建会被拦下

## 旧界面

- **两套主题**，关于页「偏好与隐私」里切换，选择存 localStorage、刷新后保持：
  - **冷蓝圆角**（默认）：`#f2f4f8` 底、大圆角卡片、柔和阴影、蓝色主按钮
  - **暖灰极简**：`#f3f3f0` 底、方角卡片、细分隔线、纯黑主按钮
- 两套主题共用同一套结构，只换样式表；页头左上角的小图标已去掉
- 页签带图标，配置页有规则分组与「规则 N 条」计数，条件字段未开启时置灰

## 上报

- `kernel_version` 之前取错字段（`awk '{print $3}' /proc/version` 拿到的仍是内核版本串，与 `kernel_release` 重复），改为取构建 banner
- 服务端开始保存 `kernel_release` / `kernel_version`，用于按 KMI 统计与兼容性排查；隐私文案同步更新（明写「服务端会保存」）

## 默认值变更

- **Probe PID Guard 默认关闭**（1.2.7 是默认开启）：出厂 `config/pid_guard.conf` 改为 `enabled=0`，需要时在「PID 隐藏」页打开
- 升级时只有旧配置仍是 1.2.7 出厂原样才自动迁移为关闭；改过 UID / comm 或显式设过 `enabled` 的配置保持不动

## 不变

- Probe PID Guard 仍是 Beta：真机只在 6.6.77 验证，其余五套 KMI 只编译
- 其余行为与 1.2.7 相同（PID 隐藏页、sus_path 陈旧 inode 修复、安全加固、7 天日志保留、单设备 5 条 / 全站 2000 条上限）

## 验证

- 离线 35/35、门禁 5/5、`I18N_OK`；构建可复现
- 真机（6.6.77 / android15-6.6）：1.2.8 安装、`integrity=ok`、PID Guard 装载与隐藏、主题切换、隐私卡开关
- 未验证：其余 5 套 KMI；冷启动首次装载（临时 root 重启即失效）

**产物**：`susfs_allinone-1.2.8.zip`，13,190,738 B，sha256 `ca1fca98b1c497194eea94ce6bd2770f43f532cc9eea2bd4804b7c032d15509f`
