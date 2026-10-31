# 变更记录

| 版本 | 摘要 |
|---|---|
| 1.2.0 | 配置改为 `config.ini` 纯数据格式（不再 `source`，消除命令注入/环境劫持/路径覆盖整类风险），旧 `config.sh` 在安装期与运行时自动迁移并保留 `.bak`；WebUI 保存合并为一次 `set_bundle`（config + 5 个规则文件一次提交，校验失败整体不落盘）；`sus_mount` / `try_umount` 按 `boot_id` 记账去重（内核无查询接口，失败不记账、下次重试）；状态页新增「手动确认 BL 已解锁」开关（写独立 `state/force_bl_unlocked`，首次开启需等待 10 秒确认），修复伪回锁设备 sepolicy/VOLD 隔离被误判跳过；`ctl.sh` 固定模块路径，不再接受环境传入的 `MODDIR`/`CONFIG`/`STATE`；配置校验拒绝保留键与重复键，通用写入命令无法改写 BL 标记；关于页贡献者卡片增加滚动触发动效；新增 `ctl.sh caps`（能力查询）与 `ctl.sh compat`（兼容性检查）；Scene 隐藏改为按内容特征重扫（apply 内三轮重试 + `ctl.sh rescan_scene` + WebUI「重扫 Scene」按钮）；预设不再收录随机命名的 Scene 目录；修复 `rescan_scene` / `guard_status` 退出码非零导致 WebUI 把成功误报为失败；修复「重扫 Scene」按钮排版；新增「自动 try_umount（模块挂载）」与「跳过系统正常挂载」；开机只执行一次 apply（去掉 45 秒后的补跑）；能力判定改为只读特性位并在实测失败后降级；自动 try_umount 默认关闭且强制过滤真实分区并记录清单；跳过隐藏列表改为 config/skip_hide.txt 可配置；不再改写管理器目录下的 ksu_susfs；sus_path 清理改为只移除本模块上次写入的规则（`replace_rules=1`），整表清空需显式设 `2`，不再默认清掉其他隐藏模块的规则；选择 KMI 改用真实内核（`/proc/version` / `real_uname.txt`），避免 uname 伪装导致选错 `.ko`；移除「强制隐藏 LSPosed」及其 ksud 全局挂载登记（会越界影响其他模块的挂载）；运行时能力探测与 `ctl.sh diag`；管理器 `ksu_susfs` 无法执行时回退到模块备份（不写盘）；非绝对路径与失败探测不再刷日志；安装保留配置 + 配置自愈；apply 加互斥锁与 10 分钟残留自愈 |
| 1.1.9 | 启动守卫（防重启循环，覆盖 late-load）；BL 解锁检测与 `bootloader=` 状态；仅解锁可用的 sepolicy / VOLD 隔离（未解锁时整组隐藏）；隐藏 GAPPS / DEX2OAT / Scene 痕迹；预设隐藏项弹窗；`kmiinfo` 与工具链修正；BakaSU 识别（与 ReSukiSU 包名相同，显示组合名 + `manager_name` 覆盖）；清理死代码（`read_entries`、重复快照调用、未用样式），开机门禁合并为 `boot_gate_ok` |
| 1.1.8 | 内核诊断 `kmiinfo`；强制 KMI 下拉；匹配失败仍可安装；uname 伪装与自动还原、开机真实内核快照；加载失败自动弹窗；修注释行被当规则下发、描述写入转义、`force_kmi` 白名单、配置内容校验 |
| 1.1.7 | 新增 5 个隐藏开关（KSU LOOP / REVANCED / 自定义 ROM / COMPAT MATRIX / CMDLINE）；修复热重启后 hide_modules 丢失；内核特性门控；构建增加 JS 语法检查 |
| 1.1.6 | 第三方声明补充 SUSFS 原始作者 simonpunk；构建可复现（固定时间戳） |
| 1.1.5 | 显示名改为 LKM SUSFS管理器；移除 WebUI 页头图标 |
| 1.1.4 | 修复 1.1.3 的 CRLF 缺陷；构建期 CR 门禁 |
| 1.1.2 | 开源协议合规：AGPL 全文、NOTICE、provenance 扩展 |
| 1.1.1 | 启动加固：load.sh 超时、半加载保护 |
| 1.1.0 | 首个整合版本 |