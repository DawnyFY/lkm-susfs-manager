# LKM SUSFS管理器 v1.2.6

> 增加管理器内更新提示（updateJson），并保留 1.2.5 的 kallsyms 回退与 1.2.4 的审计修复。APatch 仍是实验性，真机未验收。

## 重点变化

- **sus_path_loop 延迟路径规则**：新增 `config/sus_path_loop.txt` 和 WebUI 编辑框；路径暂不存在时由内核 pending 解析，上游有界重试；boot_id 账本避免重复注册，失败在 apply.log 明确报告。
- **WebUI 公告卡片**：状态页顶部显示当前发布/候选版本说明，并提供 `https://susfs.stdawns.top/` 发布页入口。
- **手动日志导出**：日志页新增「导出日志」，写入 `/sdcard/Download/susfs_allinone-log-*.txt`（含 status、load.log、apply.log）。
- **管理器内更新提示**：module.prop 增加 updateJson，仓库根目录增加 update.json（version/versionCode/zipUrl/changelog）；KernelSU / SukiSU / Magisk 模块页会显示新版本，CI 校验 update.json 与 module.prop 一致。
- **修复锁定 kallsyms 的 Android 16 / 6.12 设备**：susfs_insmod 在 kptr_restrict 导致 /proc/kallsyms 全零地址时 fail-closed（rc=13）；1.2.5 自动回退到 KernelSU ksud insmod，走 KSU_IOCTL_LOOKUP_SYMBOLS 内核侧符号解析并重写 SHN_ABS。需要 KernelSU UAPI v6+；旧版仍会失败。
- **SUSFS LKM 升级到 r18.9**：上游修复 #167（避免把 bind mount 设备路径当 source identity，可能影响 /data 父目录的 mountinfo）、#184（Termux 下无隐藏名时恢复 mkdirat 处理）、#192（改用 KallRecon 符号解析器）、#197（/proc/modules hook 目标校验失败时 fail closed，避免 kernel panic）。
- **状态读取提速**：KernelPatch 探测增加单进程 + 按 boot_id 的缓存，WebUI 刷新不再每次完整读 dmesg；状态页和保存后的刷新应明显快于 1.2.3。
- **审计遗留修复**：配置校验 `fake_cmdline_value` 引号分支、完整性缓存 ctime 防回拨、`allow_lkm` 备份恢复、`set_bundle` 半套写入回滚（含新建文件清理）、`import_legacy` 原子写入、并发 apply 状态覆盖、`check_zip` 版本排序，以及 `kp_probe`/`.manager` 原子写与 unknown 不落盘。
- **发布门禁**：`check_zip` 逐文件校验 manifest；`check_license_compliance` 按版本号取最新包；CI 用 `tools/release_manifest.sha256` 固定清单 hash，防止未来漂移。
- **文档/元数据**：NOTICE、UPSTREAM、KMI、provenance 更新到 r18.9 / `v1.5.2+_R28`；配置示例去掉 WebUI 不接受的行内注释；KMI 匹配顺序补充 tag 不配对兜底与 SDK 31/32。

## 验证

- 离线测试：32/32
- `check_no_crlf` / `check_zip` / `check_license_compliance` / `check_release_manifest` / `check_update_json` 通过
- 1.2.5 已在原设备完成冷启动自动加载、boot guard 自愈和 RCQ 热重启验证；1.2.6 的 updateJson 管理器提示待发布后验证

## 已知限制

- **APatch 仍是实验性**：默认不自动加载 LKM；QEMU 模块路径验证通过，但真机未验收。
- 1.2.5 的 kallsyms 回退仅限 KernelSU：Magisk / APatch 没有 ksud insmod 内核侧解析入口，仍走 susfs_insmod，同类锁定内核可能仍失败。
- **sus_path 持续隐藏缺口**：目录删除重建后旧 inode 规则失效；重新挂接原型未合并。
- **Magisk**：代码适配，真机冷启动未验证。
- **NeoZygisk**：r18.8 曾有外部反馈的 `/data/adb` 整目录隐藏导致 zygote 循环风险；r18.9 未复测。使用 NeoZygisk 时请删除 `/data/adb` 行，不要假定排除子目录能抵消父目录隐藏。
- 其余 7 个 KMI、官方 KernelSU / ReSukiSU / BakaSU / KernelSU Next 实机组合未逐项验证。

## 升级 / 回滚

- 升级：覆盖安装；`config/`、`state/` 保留。1.2.6 沿用版本变化清理逻辑，会清掉旧的 `autoload_paused` / `fail_count` / `state/loading` / `boot_guard`，避免 1.2.4 的暂停状态阻断新加载路径。
- 已加载旧 LKM 时，新 `.ko` 需要**冷启动**才会重新加载；热重启不会替换已加载的 LKM。
- 回滚：恢复上一版本 zip；如需回到 r18.8，同时恢复旧 `lib/*.ko` 与 `bin/susfs_insmod`。

## 校验

- 文件：`susfs_allinone-1.2.6.zip`
- 大小：12,640,083 B
- sha256：a70cde7fd08b29dc4c0b756594228d3e856f4984696c567363ae637cdc79d430

## 说明

r18.9 是上游的修复版本，但仍建议先在测试设备冷启动确认 LKM 加载与规则正常，再用于主力机。
