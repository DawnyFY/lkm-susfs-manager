# LKM SUSFS管理器 1.2.2

两件事：**英文界面** 和 **Magisk 兼容**。

## 英文界面

默认跟随系统语言：英文系统自动显示英文，中文系统保持中文。也可以在「关于」页手动切换（写 localStorage 后重载页面）。

| 项 | 说明 |
|---|---|
| 覆盖范围 | 235 条文案：状态页 / 配置页 / 日志页 / 关于页、开关说明、确认弹窗、横幅提示、错误文案、模块运行描述 |
| 动态内容 | 版本号、路径、规则数等按模式翻译，例如 `✅ Running \| 3 rules \| 6.6.77 \| v2.3.0-r18.8` |
| 不误翻 | 没有词典条目的内容原样保留，日志正文、路径、包名不会被改写 |
| 切换方式 | 关于页「Language」→ 中文 / English，选中后整页重载，不残留中英混排 |

新增一条离线测试（`tools/test_i18n.sh` + `tools/i18n_audit.js`）：校验 index.html 的每段文案与占位符、app.js 每段渲染文案都有译文，并断言行内标签拼接后英文片段之间必须有空格——避免出现 `Forfake-lockeddevices` 这种中文直拼后遗症。

## Magisk 兼容

之前只认 KernelSU 系列，Magisk 用户装不上，也不会有开机自动应用。

| 项 | 说明 |
|---|---|
| 安装 | 安装脚本放行 `MAGISK_VER` / `MAGISK_VER_CODE` / `/data/adb/magisk`，不再直接 abort |
| 开机入口 | 新增 `service.sh`：Magisk 没有 `boot-completed`，规则在 late_start 应用；KernelSU / APatch 已有 `boot-completed.sh`，这里直接跳过，不会重复执行 |
| 启动守卫 | 只有应用成功（rc=0）才清除守卫标记，与 KernelSU 路径一致；否则 Magisk 下守卫永远不会清除，每次开机都会误判「上次没启动完成」而暂停自动加载 |
| 权限 | 安装脚本给 `service.sh` 设 0755 |

**说明**：我没有 Magisk 真机，Magisk 这条路径属于新增实现、未在真机实测（KernelSU / SukiSU 路径的回归测试通过）。安装与开机应用按 Magisk 生命周期实现（`post-fs-data` + `service`），遇到问题请反馈日志。

## 修的问题

- 关于页里 LKM 版本号写死成 `v2.3.0-r18.6`，实际从 1.2.1 起就是 `v2.3.0-r18.8`，已改。
- `module.prop` 描述补上 Magisk。

## 升级

管理器里覆盖安装即可，配置与规则文件全部保留。KernelSU 系安装到 `modules_update`，**需要重启一次生效**；重启后 LKM 会重新加载，规则重新应用。

- 文件：`susfs_allinone-1.2.2.zip`
- 大小：11053928 字节
- SHA256：`21d11bef82c313db6b78a062e6710e7e453007c8ced4ebcaddb744362cfb3e49`
- 离线测试：18 项全绿
