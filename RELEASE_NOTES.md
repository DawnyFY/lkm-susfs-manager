# LKM SUSFS管理器 v1.3.0

> 1.3.0 加了首次配置向导与启动动画，并把「内存里改规则」的几个老问题修干净：
> 向导不会再把规则写空、apply 锁不会永久卡死、pstore 崩溃判定按调用栈归属而不是靠文件名。
> 没有新增必选项，配置格式未变，覆盖安装保留 config/ 与 state/。

## 重点变化

- **首次配置向导（五步）**：内核匹配 → 隐藏项 → 隐藏路径 → 自动加载与统计 → 保存并应用；关于页可重进
- **启动动画**：首次打开 WebUI 播一次（纯 CSS，光刃旋转 + 幕布拉开，可点击/Esc 跳过）
- **AVC 日志伪装在官方 KernelSU 上也能开**：CLI 没有 `enable_avc_log_spoofing` 时自动改走 LKM 参数 `avc_su_ctx`，关闭时还原原值
- **pstore 崩溃判定改为按调用栈归属**：转储里出现模块加载日志不再等于"本模块崩溃"，别人的 panic 不会暂停自动加载
- **apply 锁**：`state/.lock.mutex` 残留会按 mtime（≥30 s）与 pid 状态回收，不再永久「另一个 apply 正在运行」

## 修掉的问题

| 问题 | 症状 |
|---|---|
| 向导写盘没有守卫 | `get_bundle` 失败时把 7 个规则文件写成 0 字节，界面仍回「已保存」 |
| `.lock.mutex` 不回收 | pid 缺失/损坏/被复用后 apply 永久卡死，只能手删目录 |
| 关闭 AVC 会覆盖用户值 | 硬编码写回 `u:r:ksu:s0`，自定义 su 域设备上原值丢失 |
| 向导「匿名统计」是死控件 | 关掉也会继续上报 |
| pstore 判定太慢 | 12 MB 转储时 `status` 从 ~1.9 s 涨到 30 s+ |
| `withBusy` 布尔标志 | 两个并发任务时 `busy` 提前复位，按钮在任务中重新可用 |

## 兼容性

- 配置格式不变；覆盖安装保留 `config/`、`state/`
- 新增出厂默认：`avc_spoof=1`（仅影响新装；老配置不覆盖）
- 已发布 1.2.9 的用户升级后不会丢规则；`state/.lock.mutex` 若已残留，本版会自动回收

## 验证

- 离线 49/49、Vitest 56/56、门禁 5/5、`I18N_OK keys=194`；两次构建字节一致
- 真机（6.6.77 / android15-6.6 / KernelSU 3.0.0）：`integrity=ok`、`rules` 与配置一致、AVC 参数按配置设置与还原
- 1.2.9 ↔ 1.3.0 双向覆盖安装：9 个配置文件与 state 逐文件 sha256 全等

## 下载

- <https://github.com/DawnyFY/lkm-susfs-manager/releases>
- 发布页与校验值：<https://susfs.stdawns.top/>
