# 剩余步骤与验收清单

> 这是必须在真实设备上完成的顺序。每一步先让用户确认；不要自行重启、刷机或卸载模块。  
> 本文含本地路径示例；若要公开，先按 `SANITIZATION.md` 脱敏。

---

## 阶段 A — 冷启动前准备

- [ ] 用户在场，确认可以重启；说明重启后需要重新走 SukiSU 临时 root。
- [ ] 确认 `susfs4ksu` 与 `susfs_oneshot` 仍启用（当前是）。
- [ ] 备份当前配置：`device_snapshot/backups/` 已有；可再拉一次。
- [ ] 记录当前 ZIP（1.1.5）SHA256：`4E20DD0C...0FF8`。
- [ ] 确认没有执行 `rmmod susfs_guard_lkm`。
- [ ] 确认 `module.prop` 的 ID 仍为 `susfs_allinone`，没有改版本。
- [ ] 把 `tools/verify_after_boot.sh` 推到设备：

```powershell
adb push tools\verify_after_boot.sh /data/local/tmp/verify_after_boot.sh
```

> 当前 adb shell 可能是 root（`u:r:ksu:s0`），但重启后未必；如果脚本无法运行，用 SukiSU 的模块 Action/终端执行。

---

## 阶段 B — 重启与临时 root

按用户既有流程执行，不要改变顺序：

1. 正常重启设备。
2. 等待系统启动；此时 root 可能不可用，这是临时 root 环境的预期。
3. 按用户流程将 SELinux 设为宽容（permissive）。
4. 打开 SukiSU Ultra。
5. 执行 exploit / 临时 root。
6. 在 SukiSU 中刷新/重新加载模块，确认 `/data/adb/modules_update/susfs_allinone` 合并。
7. 按用户流程做 hot reboot（软重启），让模块的 `post-fs-data` / `boot-completed` 在 root 环境执行。

**不要**：

- 不要走 EDL/9008。
- 不要 `fastboot flash boot/init_boot`。
- 不要解锁 bootloader。
- 不要在未确认时删除 `/data/adb/modules_update/susfs_allinone`。
- 不要 `rmmod susfs_guard_lkm`。

如果用户流程与上述措辞不同，以用户实际步骤为准；接收方只记录并验证，不擅自发明 exploit 操作。

---

## 阶段 C — 冷启动验证（核心）

### C1. 运行只读验证

```sh
sh /data/local/tmp/verify_after_boot.sh 8
```

若没有 uid-0 shell：

```sh
su -c 'sh /data/local/tmp/verify_after_boot.sh 8'
```

或在 SukiSU 的模块 Action/WebUI 终端执行。脚本不会加载/卸载 LKM，也不会 apply。

> 以最后一行 `VERIFY_RESULT=OK/FAIL` 为准。部分 adb/Windows 组合不会把设备端退出码传回；不要只看 PowerShell 的 `$LASTEXITCODE`。  
> 重启前的预跑记录在 `device_snapshot/verify_after_boot_current.txt`：因为 `modules_update` 还在，预期显示 `FAIL`，这不是模块故障。

### C2. 期望结果

```text
lkm_present=1
lkm_variant=GKI-LKM
lkm_version=v2.3.0
rules=8
hide_kernelsu=1
marker=1
auto_load=1
root_manager=SukiSU
ksu_bin=ok
fail_count=0
VERIFY_RESULT=OK
```

同时：

- [ ] `/data/adb/modules_update/susfs_allinone` 已消失（pending update 合并）。
- [ ] `load.log` 有新的冷启动记录，包含 KMI 选择/`susfs_insmod` 或“已存在”路径。
- [ ] `apply.log` 有新记录，8 条 `sus_path` 写入，`apply ok`。
- [ ] `/proc/susfs_path` 有 17 行左右（9 LKM + 8 用户），用户唯一规则 8。
- [ ] `marker` 存在。
- [ ] `susfs4ksu`、`susfs_oneshot` 仍启用（此时先不动）。

### C3. 失败处理

| 失败 | 先做什么 | 不要做什么 |
|---|---|---|
| `lkm_present=0` | 看 `load.log`；确认 KMI；执行模块 Action 手动加载；保存日志 | 不要 `rmmod`；不要刷 boot |
| `lkm_present=1` 但 `rules=0` | 看 `apply.log`；手动 Action；确认 `/sdcard/Android/data` | 不要直接改 `/proc/susfs_path` 后不验证 |
| `ksu_bin=incompatible` | 确认是否回退到 `module/bin/ksu_susfs_good`；看日志 | 不要覆盖分支自带二进制 |
| `modules_update` 仍在 | 确认管理器是否合并；重新安装/重启前先问用户 | 不要手删活动模块 |
| `root_manager=Unknown` | 确认 SukiSU 包名/管理器状态；`pm list packages` | 不要据此判定 LKM 失败 |

如果自动链路失败但 Action 手动成功，记录为“自动加载未通过”，不要把它当成通过。

### C4. 保存证据

```powershell
python tools\capture_device_snapshot.py
```

把新的 `status.txt`、`load.log`、`apply.log` 覆盖到 `device_snapshot/`，并更新 `TEST_RESULTS.md` / `DEVICE_STATE.md`。  
如果 `load.log`/`apply.log` 被截断，先拉完整文件再操作。

---

## 阶段 D — 停用旧模块并复测

只有阶段 C 全部通过后才做。

### D1. 停用（不是删除）

在 SukiSU 模块列表中：

- [ ] 禁用 `susfs4ksu`（SUSFS-FOR-KERNELSU）。
- [ ] 禁用 `susfs_oneshot`（SUSFS 一键恢复）。
- [ ] 保留 `susfs_allinone` 启用。
- [ ] 保留 Zygisk Next/LSPosed 等其他模块不动。

文件方式（备用，需 root）：

```sh
touch /data/adb/modules/susfs4ksu/disable
touch /data/adb/modules/susfs_oneshot/disable
```

不要删除目录；需要回退时可移除 `disable`。

### D2. 再次冷启动

- [ ] 重启 + 临时 root + hot reboot（同阶段 B）。
- [ ] 再跑 `verify_after_boot.sh 8`。
- [ ] 期望仍为 `lkm_present=1`、`rules=8`、`auto_load=1`、`ksu_bin=ok`、`fail_count=0`。
- [ ] 确认旧模块没有再往 `/proc/susfs_path` 写重复规则。
- [ ] 如果失败，先移除旧模块的 `disable` 回退，不要 `rmmod`。

### D3. 旧模块去留

- 通过后可以保持禁用一段时间，不要立刻删除；确认多次重启/日常使用稳定后再决定是否卸载。
- 卸载前备份 `/data/adb/susfs4ksu` 配置和当前 `device_snapshot/`。

---

## 阶段 E — 真实 WebUI 验收

在 SukiSU 中打开 **SUSFS 管理器** WebUI。

- [ ] 状态页显示模块版本 `1.1.0`、`root_manager=SukiSU`、`ksu_bin_path`、KMI、LKM 版本、规则 8、auto_load 1。
- [ ] 配置页可读取 8 条 `sus_path`、`hide_modules=kernelsu`；保存后配置不丢。
- [ ] 日志页显示 `load.log` / `apply.log`；内容正常，无乱码。
- [ ] 关于页版本/说明正常。
- [ ] 切换浅色/深色主题；无外部 CDN 请求。
- [ ] 修改一个无害配置项并保存，再恢复；不要改 `auto_load`/`replace_rules` 做危险测试。
- [ ] 在 WebUI 执行“应用”后，`ctl status` 仍为 8 条规则。
- [ ] 如果 WebUI 空白：检查 `webroot` 权限/`ksud module list` 的 `web=true`；先 `ctl.sh status` 验证后端，不要急着重装。

当前只做过本地 mock 预览；这一步是第一次真实 WebView 验收。

---

## 阶段 F — Wild Detector 复测

目标：**实验检测开启时仍然干净**。

### F1. 确认当前实验开关状态

上一轮使用的 Wild Detector DataStore：

```text
/data/data/com.wildkernels.wilddetector/files/datastore/app_settings.pb
```

快照中该文件为 2 字节：

```text
38 01
```

这对应上一轮实验检测状态。先备份：

```sh
cp /data/data/com.wildkernels.wilddetector/files/datastore/app_settings.pb \
   /data/local/tmp/wd_app_settings.pb.bak
```

> 该文件是应用私有数据；如果当前状态不是实验开启，恢复上一轮备份后再测。不要在没有备份时直接覆盖。

### F2. 强制停止并重开

```sh
am force-stop com.wildkernels.wilddetector
```

然后从桌面重新打开。**不要按应用内的刷新按钮**（v24 的刷新可能回到非实验状态/触发不同逻辑）。

### F3. 扫描与记录

- [ ] 执行完整扫描。
- [ ] 确认实验检测项已开启（按上一轮状态）。
- [ ] 记录结果截图/检测项列表。
- [ ] 期望：无 SUSFS/root/模块相关检测。
- [ ] 如果出现检测：记录准确名称、路径、时间；检查 `rules`、`hide_modules`、旧模块是否已禁用、`/proc/susfs_path`；不要盲目加规则。

### F4. 恢复

测试后如需恢复原 DataStore，使用备份文件覆盖并再次 `am force-stop`；不要 `pm clear`（会清掉其他应用设置）。

---

## 阶段 G — GitHub 发布（设备验收后）

- [ ] 读 `GITHUB_HANDOFF.md` 和 `SANITIZATION.md`。
- [ ] 只把 `module/`、`tools/`、公开文档、`LICENSE`/`provenance` 放进仓库。
- [ ] 排除 `conversation/`、`device_snapshot/`、`backups/`、`preview/`（预览图/截图可能含设备信息）。
- [ ] 搜索并删除设备序列号、`C:\Users\<user>`、`D:\aimod`、其他模块列表、个人日志。
- [ ] 让用户确认仓库公开/私有、账号、仓库名。
- [ ] 提交、tag `v1.1.0`、上传 Release ZIP、核对 SHA256。
- [ ] README 写明：锁定 bootloader + 临时 root 的实验性方案、只测试 SukiSU/当前设备、冷启动验证边界、风险。

---

## 阶段 H — 最终验收

全部通过后更新：

- [ ] `docs/TEST_RESULTS.md`：冷启动、旧模块停用、WebUI、Wild Detector 结果。
- [ ] `docs/DEVICE_STATE.md`：新的 `status.txt`、日志、`modules_update` 状态。
- [ ] `tools/verify_after_boot.sh` 的预期（如果规则数改变）。
- [ ] 若改了模块源码：重新构建 ZIP，更新 SHA256、`check_zip.py` 预期、`START_HERE.md` 哈希。
- [ ] 重新生成 `MANIFEST.sha256` 和交接 ZIP（如果文档/产物有变化）。
- [ ] 给用户一份简短结论：哪些通过、哪些仍有风险、是否需要继续。

---

## 快速检查表

```text
[ ] 冷启动 load.log 新记录
[ ] 冷启动 apply.log 8 条
[ ] lkm_present=1
[ ] rules=8
[ ] auto_load=1
[ ] root_manager=SukiSU
[ ] ksu_bin=ok
[ ] fail_count=0
[ ] modules_update 已合并
[ ] 旧模块已停用（阶段 D 后）
[ ] 停用旧模块后仍 8 条
[ ] 真实 WebUI 四页
[ ] Wild Detector 实验检测干净
[ ] GitHub 脱敏/Release
```
