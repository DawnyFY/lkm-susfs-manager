# LKM SUSFS管理器 v1.2.4

> 同步上游 SUSFS LKM r18.9，并修复上一轮审计遗留问题。APatch 仍是实验性，真机未验收。

## 重点变化

- **SUSFS LKM 升级到 r18.9**：上游修复 #167（避免把 bind mount 设备路径当 source identity，可能影响 /data 父目录的 mountinfo）、#184（Termux 下无隐藏名时恢复 mkdirat 处理）、#192（改用 KallRecon 符号解析器）、#197（/proc/modules hook 目标校验失败时 fail closed，避免 kernel panic）。
- **状态读取提速**：KernelPatch 探测增加单进程 + 按 boot_id 的缓存，WebUI 刷新不再每次完整读 dmesg；状态页和保存后的刷新应明显快于 1.2.3。
- **审计遗留修复**：配置校验 `fake_cmdline_value` 引号分支、完整性缓存 ctime 防回拨、`allow_lkm` 备份恢复、`set_bundle` 半套写入回滚（含新建文件清理）、`import_legacy` 原子写入、并发 apply 状态覆盖、`check_zip` 版本排序，以及 `kp_probe`/`.manager` 原子写与 unknown 不落盘。
- **发布门禁**：`check_zip` 逐文件校验 manifest；`check_license_compliance` 按版本号取最新包；CI 用 `tools/release_manifest.sha256` 固定清单 hash，防止未来漂移。
- **文档/元数据**：NOTICE、UPSTREAM、KMI、provenance 更新到 r18.9 / `v1.5.2+_R28`；配置示例去掉 WebUI 不接受的行内注释；KMI 匹配顺序补充 tag 不配对兜底与 SDK 31/32。

## 验证

- 离线测试：30/30（新增 F7/F8/F9、探测缓存 unknown 重试与发布引用一致性断言）
- `check_no_crlf` / `check_zip` / `check_license_compliance` / `check_release_manifest` 通过（check_zip 现在逐文件校验 manifest）
- 设备回归（2026-11-09 冷启动）：模块 1.2.4 加载 r18.9（3,101,664 B / 116 symbols）；LKM/规则/integrity 正常；LSPosed connected；status 冷缓存后约 1.35-1.45s，get_config ~45ms，apply ~1.4s

## 已知限制

- **APatch 仍是实验性**：默认不自动加载 LKM；QEMU 模块路径验证通过，但真机未验收。
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
- 大小：12,636,429 B
- sha256：443996702f99a2f0a91cadab510d46b7f4958a80e65996b11fae86f510ec483d

## 说明

r18.9 是上游的修复版本，但仍建议先在测试设备冷启动确认 LKM 加载与规则正常，再用于主力机。
