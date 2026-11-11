# LKM SUSFS管理器 v1.2.5

> 修复锁定 kallsyms 的 Android 16 / 6.12 设备 LKM 加载失败；保留 r18.9 与 1.2.4 的审计修复。APatch 仍是实验性，真机未验收。

## 重点变化

- **修复锁定 kallsyms 的 Android 16 / 6.12 设备**：susfs_insmod 在 kptr_restrict 导致 /proc/kallsyms 全零地址时 fail-closed（rc=13）；1.2.5 自动回退到 KernelSU ksud insmod，走 KSU_IOCTL_LOOKUP_SYMBOLS 内核侧符号解析并重写 SHN_ABS。需要 KernelSU UAPI v6+；旧版仍会失败。
- **SUSFS LKM 升级到 r18.9**：上游修复 #167（避免把 bind mount 设备路径当 source identity，可能影响 /data 父目录的 mountinfo）、#184（Termux 下无隐藏名时恢复 mkdirat 处理）、#192（改用 KallRecon 符号解析器）、#197（/proc/modules hook 目标校验失败时 fail closed，避免 kernel panic）。
- **状态读取提速**：KernelPatch 探测增加单进程 + 按 boot_id 的缓存，WebUI 刷新不再每次完整读 dmesg；状态页和保存后的刷新应明显快于 1.2.3。
- **审计遗留修复**：配置校验 `fake_cmdline_value` 引号分支、完整性缓存 ctime 防回拨、`allow_lkm` 备份恢复、`set_bundle` 半套写入回滚（含新建文件清理）、`import_legacy` 原子写入、并发 apply 状态覆盖、`check_zip` 版本排序，以及 `kp_probe`/`.manager` 原子写与 unknown 不落盘。
- **发布门禁**：`check_zip` 逐文件校验 manifest；`check_license_compliance` 按版本号取最新包；CI 用 `tools/release_manifest.sha256` 固定清单 hash，防止未来漂移。
- **文档/元数据**：NOTICE、UPSTREAM、KMI、provenance 更新到 r18.9 / `v1.5.2+_R28`；配置示例去掉 WebUI 不接受的行内注释；KMI 匹配顺序补充 tag 不配对兜底与 SDK 31/32。

## 验证

- 离线测试：31/31（新增加载器零地址回退断言）
- `check_no_crlf` / `check_zip` / `check_license_compliance` / `check_release_manifest` 通过（check_zip 现在逐文件校验 manifest）
- 1.2.5 的零地址回退尚无设备结果；沿用 1.2.4 的 r18.9 冷启动、规则、integrity 与 UI 性能数据

## 已知限制

- **APatch 仍是实验性**：默认不自动加载 LKM；QEMU 模块路径验证通过，但真机未验收。
- 1.2.5 的 kallsyms 回退仅限 KernelSU：Magisk / APatch 没有 ksud insmod 内核侧解析入口，仍走 susfs_insmod，同类锁定内核可能仍失败。
- **sus_path 持续隐藏缺口**：目录删除重建后旧 inode 规则失效；重新挂接原型未合并。
- **Magisk**：代码适配，真机冷启动未验证。
- **NeoZygisk**：r18.8 曾有外部反馈的 `/data/adb` 整目录隐藏导致 zygote 循环风险；r18.9 未复测。使用 NeoZygisk 时请删除 `/data/adb` 行，不要假定排除子目录能抵消父目录隐藏。
- 其余 7 个 KMI、官方 KernelSU / ReSukiSU / BakaSU / KernelSU Next 实机组合未逐项验证。

## 升级 / 回滚

- 升级：覆盖安装；`config/`、`state/` 保留。
- 已加载旧 LKM 时，新 `.ko` 需要**冷启动**才会重新加载；热重启不会替换已加载的 LKM。
- 回滚：恢复上一版本 zip；如需回到 r18.8，同时恢复旧 `lib/*.ko` 与 `bin/susfs_insmod`。

## 校验

- 文件：`susfs_allinone-1.2.4.zip`
- 大小：12,636,835 B
- sha256：57c7e79afdca28dc20fbab6f420403f0b0a53e27709bfc2e63c0310926b088af

## 说明

r18.9 是上游的修复版本，但仍建议先在测试设备冷启动确认 LKM 加载与规则正常，再用于主力机。
