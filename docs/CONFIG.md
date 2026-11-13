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
- `config/hide_modules.txt`：默认 `kernelsu`；
- `config/sus_map.txt`：隐藏进程 maps 中的真实文件路径；
- `config/allow_lkm_on_kernelpatch`：APatch 放行标记（独立文件，不在 config.ini）。

## WebUI

在管理器打开模块 WebUI：

| 页面 | 内容 |
|---|---|
| 状态 | LKM 版本、KMI、规则数、SELinux、二进制路径、失败计数；APatch 环境额外显示 APatch 卡片 |
| 配置 | 图形化编辑规则与开关；强制指定 KMI |
| 日志 | `load.log` / `apply.log` 在线查看；可手动导出到 `/sdcard/Download` |
| 关于 | 版本、致谢、许可证摘要、语言切换 |

APatch 卡片：

- APatch 用户态；
- KernelPatch 内核（有版本时显示，如 `已激活 (d09)`）；
- 共存模式；
- SUSFS LKM 放行状态；
- 「放行 LKM / 取消放行」按钮（带风险确认）。

KSU / Magisk 环境不显示该卡片。

## 状态字段

常用 `ctl.sh status` 字段：

- `lkm_present` / `lkm_version` / `lkm_variant`
- `rules` / `apply_result` / `apply_fails`
- `integrity`
- `kernelpatch` / `apatch_userland` / `kernelpatch_kernel` / `kernelpatch_version`
- `coexist_mode` / `allow_lkm`
- `root_manager` / `selinux` / `bootloader`

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
