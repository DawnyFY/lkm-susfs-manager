# 配置与 WebUI

## 配置文件

`config/config.ini`（纯 `KEY=VALUE`，不会被执行）：

```ini
auto_load=1
hide_sus_mnts=1
avc_spoof=0
replace_rules=0
```

> 配置值里不要写行内注释。WebUI 保存会拒绝“值含空白”的行；注释请单独占一行（以 `#` 开头）。auto_load=1 表示开机自动加载并应用；hide_sus_mnts=1 隐藏 SUS 挂载点；avc_spoof=0 默认关闭；replace_rules=0 只追加。

其他配置：

- `config/config.ini`：模块通用开关；
- `config/sus_path.txt`：每行一个路径，`#` 开头为注释；
- `config/sus_mount.txt` / `try_umount.txt`：挂载规则；
- `config/pid_guard.conf`：Probe PID Guard（1.2.7+，可选组件）的开关与目标，见下节；
- `config/hide_modules.txt`：默认 `kernelsu`；
- `config/sus_map.txt`：隐藏进程 maps 中的真实文件路径；
- `config/allow_lkm_on_kernelpatch`：APatch 放行标记（独立文件，不在 config.ini）。

## WebUI

在管理器打开模块 WebUI：

| 页面 | 内容 |
|---|---|
| 状态 | LKM 版本、KMI、规则数、SELinux、二进制路径、失败计数；APatch 环境额外显示 APatch 卡片 |
| 配置 | 图形化编辑规则与开关；强制指定 KMI |
| PID 隐藏 | Probe PID Guard 的状态与配置（1.2.7+）：六张状态卡 + 目标 UID/comm；保存即重载该组件 |
| 日志 | `load.log` / `apply.log` 在线查看；可手动导出到 `/sdcard/Download` |
| 关于 | 版本、致谢、许可证摘要、语言切换、匿名统计开关 |

APatch 卡片：

- APatch 用户态；
- KernelPatch 内核（有版本时显示，如 `已激活 (d09)`）；
- 共存模式；
- SUSFS LKM 放行状态；
- 「放行 LKM / 取消放行」按钮（带风险确认）。

KSU / Magisk 环境不显示该卡片。

## WebUI 保存的容量上限

WebUI 保存通过 `ctl.sh set_bundle` 一次写入 `config.ini` + 7 个规则文件，
参数经由命令行传递，受内核 `ARG_MAX` 限制：

- 原始内容合计约 **70 KB** 以内安全（base64 双层编码约 1.78× 膨胀）
- 超出后 `exec` 直接失败（`Argument list too long`），**不会写入半截文件**
- 单个规则文件写得很大时，建议改用命令行（`ctl.sh set_file <name> <b64>`）或分文件编辑

## Probe PID Guard（1.2.7+，可选）

自研内核模块 `generic_pid_guard`，用 `kretprobe __arm64_sys_getppid` 对匹配进程伪装 `getppid`。
WebUI「PID 隐藏」页可视化编辑，等价的配置文件是 `config/pid_guard.conf`：

```ini
# Probe PID Guard（默认关闭）
enabled=0
# comma-separated UID ranges
target_uids=99000-99999
# comma-separated comm prefixes, * suffix allowed
target_comms=probe-*,canProbe*,ivecheck*
# never match these comms
exclude_comms=nqiunativecheck
```

规则：

- 只按固定键解析，**不会**被 shell 执行（`$()` / `;` 无效）；
- 值里不允许空白、空项、尾随逗号；`target_uids` 只接受数字或 `数字-数字`；
- 裸 `*` 会被拒绝——空前缀在内核侧同样判为不匹配，不会命中全部进程；
- `target_uids` 与 `target_comms` 不能同时为空；
- 参数在 insmod 时生效；sysfs `parameters/` 为 `0440`，仅 root 可读。

生效方式：

| 操作 | 行为 |
|---|---|
| 保存（值变化） | 先 `rmmod` 再按新参数 `insmod` |
| 保存（值未变） | 幂等，不重复装载 |
| `enabled=1` → `0` | 立即卸载，并从 `/proc/susfs_hide_modules` 撤名 |
| `enabled=0` → `1` | 重新装载并重新隐藏 |
| 状态码 | `ok` / `failed` / `unloaded` / `unload_failed` / `stale` / `no_ko` / `bad_conf` / `unsupported` |

没有 `ksud` 的管理器（Magisk / APatch）记 `unsupported` 并跳过，不会每次开机写一条失败。

## 状态字段

常用 `ctl.sh status` 字段：

- `lkm_present` / `lkm_version` / `lkm_variant`
- `rules` / `apply_result` / `apply_fails`
- `integrity`
- `kernelpatch` / `apatch_userland` / `kernelpatch_kernel` / `kernelpatch_version`
- `coexist_mode` / `allow_lkm`
- `root_manager` / `selinux` / `bootloader`

`ctl.sh status` 中的 PID Guard 字段（1.2.7+）：

```
pid_guard_enabled=1
pid_guard_loaded=1
pid_guard_visible=0
pid_guard_hidden=1
pid_guard_result=ok
pid_guard_uids=99000-99999
pid_guard_comms=probe-*,canProbe*,ivecheck*
```

`pid_guard_visible` 指 `/proc/modules` 里是否仍能看到 `generic_pid_guard`；正常应为 0。
`pid_guard_hidden` 只在组件已加载时才算，卸载后不会残留「已隐藏」的假象。

## 匿名安装统计

- 开关在 WebUI「关于」页，切换即保存（写入 `config.ini` 的 `anonymous_stats`），无需再点「保存并应用」
- 发送：随机 install_id、模块版本、versionCode，以及内核版本（`kernel_release` / `kernel_version`，用于兼容性排查）
- 服务端落库只有 install_id / version / versionCode / 首次与最近时间；**内核两项接收但入库时丢弃**
- 不发送：设备型号、序列号、应用列表
- 关闭后立即删除 `state/server_token`，不再请求，失败日志也不再上传
- token 按 versionCode 绑定，升级后重新申请；剩余不足 7 天会自动重签
- 首次开机或开启开关时请求一次（`connect 10 / max 30`，失败重试一次），失败不阻塞开机

## 失败日志上传

- 只有加载/应用失败时自动上传 `load.log`/`apply.log` 尾段（约 48KB）到 `/api/v1/failure`
- 本地同时留一份快照，默认落 `state/failures`（目录 700、文件 600）；**不再自动写 `/sdcard/Download`**
- 成功/跳过不上传；没有独立开关，关闭匿名统计后无 token，也就不会上传
- 服务端只保留 7 天（单设备最多 5 条、全站最多 2000 条）；日志可能含隐藏路径，用于定位，不适合公开

## install_id / install_key

- 安装时在 `state/install_key` 生成 32 字节随机 hex，权限 600；升级时优先复用旧值
- `ctl.sh install_id` 只输出密钥的 16 位 SHA-256 前缀，用于匿名标识
- 不要把 `install_key` 发到日志/截图；密钥可被 root 读取，只适合匿名关联，不是硬件级秘密

## sus_path_loop

`sus_path_loop.txt` 用于会被删除后重建的路径。

- 每行一个绝对路径，支持 `#` 注释
- 路径可以暂时不存在；内核保存 pending 规则并在有界范围内重试解析
- 路径出现后由内核隐藏，不需要用户态常驻循环
- 模块用 boot_id 账本避免同一次启动重复注册
- 内核/`ksu_susfs` 不支持 `add_sus_path_loop` 时，apply.log 会明确报错，不会静默成功
- 仍无法做到“目录重建后旧 inode 一定自动跟上”；上游规则在重建场景下的行为需要实测，必要时重新 apply 或重启
- pending 规则的内核重试约 120 秒；超时后路径才出现时，下一次 apply 会重新注册
- 配置中删除 loop 行后，apply 会用 `/proc/susfs_path` 的 `del` 逐条撤销；若内核拒绝，日志会明确提示需重启或 `replace_rules=2`
- `replace_rules=1` 会按 `state/our_paths.txt` 删除 loop 规则；`replace_rules=2` 整表清空

## 日志导出

- 导出文件包含 status、隐藏路径、模块挂载点和 `install_id`，默认写入 `/sdcard/Download`，权限 600
- WebUI 导出前会二次确认；分享前请检查内容，用完删除

## install_id 的边界

- 仅用于安装期匿名标识/粗粒度限流
- 不是鉴权 token，不能防重放、不能作为封禁依据；root/备份可读取或克隆
