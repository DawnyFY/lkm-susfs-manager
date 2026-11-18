# LKM SUSFS管理器 1.2.7

两件事：**匿名安装统计**（默认开启）和 **Probe PID Guard**（可选内核模块）。

## 匿名安装统计

首次开机/保存配置时向 `https://susfs.stdawns.top/api/v1/install` 申请一次版本绑定 token（`install_id` + versionCode，180 天），同版本复用。服务端只记录 `install_id` / 版本 / 首次与最近时间。关闭开关会删除本地 token 并停止请求。

仅加载/应用失败时：先在 `/sdcard/Download` 留一份快照，再把 `load.log` / `apply.log` 尾段自动上传到 `/api/v1/failure`（服务端保留 7 天）；成功时不上传。

## Probe PID Guard

对指定进程伪装 `getppid`，用于让 isolated probe 类检测进程看到错误的父进程。

**Beta**：该能力标记为实验性。真机只在 6.6.77 验证过；其余五套 KMI 只编译未运行，且 `getppid` 伪装对抗的是进程侧检测，后续检测方改动可能需要跟进。默认开启但可随时在「PID 隐藏」页关掉。

| 项 | 说明 |
|---|---|
| 实现 | `generic_pid_guard` LKM，`kretprobe __arm64_sys_getppid`，按 UID 范围与 comm 前缀匹配 |
| 默认目标 | `target_uids=99000-99999`、`target_comms=probe-*,canProbe*,ivecheck*`、`exclude_comms=nqiunativecheck` |
| KMI | 打包 5.10 / 5.15 / 6.1 / 6.6 / 6.12 / 6.18 六套，由 `load.sh` 选中的 KMI 驱动，`pid_guard.sh` 取完整 KMI 名（如 `android15-6.6`） |
| 配置 | `config/pid_guard.conf`（WebUI 配置页卡片也可改） |

### ⚠️ 行为变更：默认开启

`config/pid_guard.conf` 默认 `enabled=1`。**升级到 1.2.7 后开机即会加载该模块**，不需要额外操作；不想要就在配置页关掉，关闭会立即卸载，不残留到重启。

### 立即生效

保存配置即生效，无需重启：`apply.sh` 末尾会调用 `pid_guard.sh`。

- 参数变更（UID/comm/排除项）→ 自动 `rmmod` 后按新参数重新 `insmod`
- `enabled` 1→0 → 自动卸载
- 同一份配置重复 apply → 幂等，不重复装载

### 自隐藏

装载成功后自动写入 `/proc/susfs_hide_modules`，与 `kernelsu` 同一级隐藏：`/proc/modules` 中不再出现 `generic_pid_guard`。（`/sys/module` 侧与 `kernelsu` 现状一致，SUSFS v2.3.0 本身对该项 `failed`。）

### 失败可见

装载或卸载失败会写入 `state/pid_guard.status`，并在 `load.log` 留下原因。`ctl.sh status` 新增七个字段：

```
pid_guard_enabled=1
pid_guard_loaded=1
pid_guard_visible=0
pid_guard_hidden=1
pid_guard_result=ok        # ok / failed / unload_failed / unloaded / stale / no_ko / skipped / bad_conf / unsupported
pid_guard_uids=99000-99999
pid_guard_comms=probe-*,canProbe*,ivecheck*
```

可选组件的失败**不会**影响 SUSFS 规则下发，也不会触发「连续失败暂停自动加载」。

### 安全加固（1.2.7 审计修复）

| 项 | 说明 |
|---|---|
| 配置解析不再 source | `config/pid_guard.conf` 改为按固定键 `grep/cut` 读取。此前 `. conf` 会让 `$(...)`/`;` 以 root 执行，而且值里一个空格就按 POSIX 赋值规则把整个字段截断成空——insmod 仍成功、状态仍 `ok`，功能静默消失 |
| 写入即校验 | `pid_guard_ctl.sh` 在落盘前校验字符集、空项、裸 `*`、`enabled` 取值；不合法直接 `rejected:`，旧配置不被覆盖 |
| 裸 `*` 不再命中全部进程 | 内核 `comm_prefix()` 对空前缀返回 false；配置侧也拒绝 |
| sysfs 参数改为 0440 | 目标 UID/comm 清单不再对普通进程可读（此前 `/sys/module/generic_pid_guard/parameters/*` 是 0644） |
| 失败快照改私有目录 | 默认落 `state/failures`（0700 / 文件 0600），不再自动写 `/sdcard/Download`（FUSE 上 `chmod 600` 无效，且内容含隐藏路径） |
| Magisk/APatch 不再刷失败 | 没有 `ksud` 时记 `unsupported` 并跳过，不再每次开机写一条 insmod 失败 |
| 加载期限时 | `load.sh` 里对 `pid_guard.sh` 单独 `timeout 8`，避免顶穿外层 30s 导致误判加载失败 |
| 只重载可选组件 | 新增 `ctl.sh pid_guard_reload`；WebUI 保存只重载 guard，不跑整条 apply |

## 其他修复

- 英文界面补齐 PID Guard 卡片 11 条文案（本版引入卡片时漏了词典，`test_i18n.sh` 会守住这条）
- 安装期 `pid_guard.sh` / `pid_guard_ctl.sh` 设为 0755（此前落盘 0644，虽不影响 `sh <path>` 调用，但不符合脚本惯例）
- 新增离线测试 `tools/test_pid_guard.sh`：覆盖加载、幂等、参数变更重载、关闭卸载、卸载失败、insmod 失败、缺 ko、无配置八类路径

## 验证范围（限定）

- 真机（6.6.77 / android15-6.6）：装载、`/proc/modules` 隐藏、参数变更就地重载、关闭卸载、重新开启装载、`ctl.sh status` 五个字段全部实测
- 5.10 / 5.15 / 6.1 / 6.12 / 6.18：只做编译与打包，**未在对应内核真机运行**
- 离线：35/35 测试通过
