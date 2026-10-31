# 测试记录

> 本文档记录的是 **1.1.0 时期**的真机测试，不能代表 1.2.0。1.2.0 的验收见
> `26-audit-1.2.0-full.md` 与 `tools/test_*.sh`（离线回归）。

日期：2026-10-20  
测试对象：`susfs_allinone` 1.1.0（SUSFS 管理器）  
设备：Xiaomi 15 Ultra / Android 16 / kernel 6.6.77-android15-6.6 / SukiSU Ultra 临时 root

> 结论：**静态/宿主机/已 root 手动路径验证通过；真正冷启动未验证。**  
> 不要把“当前 LKM 已加载”当成“自动加载已验证”。

---

## 1. 汇总

| 项目 | 结果 | 说明 |
|---|---|---|
| 模块 ID/名称/版本 | PASS | `susfs_allinone` / `SUSFS 管理器` / `1.1.0` (2) |
| 旧名字清除 | PASS | 源码、WebUI、Action、安装器、已安装模块均无旧显示名 |
| Shell 语法 | PASS | 入口脚本 `sh -n` 通过 |
| WebUI JS/CSS | PASS（本地） | mock 预览浅色/深色；无外部 CDN；真实后端未验收 |
| KMI 匹配 | PASS | 当前 `6.6.77-android15...` → `android15-6.6` |
| 分支检测 | PASS（fake `pm`） | SukiSU / ReSukiSU / KernelSU Next / KernelSU / 回退 |
| 二进制回退 | PASS | `SUSFS_BIN=/system/bin/false` → `bin/ksu_susfs_good`，8 规则 |
| `action.sh` | PASS | 手动加载 + 应用，输出正常 |
| `post-fs-data.sh` | PASS（手动执行） | 在 LKM 已存在场景下跳过加载并成功 |
| `boot-completed.sh` | PASS（手动执行） | 在 LKM 已存在场景下应用 8 规则 |
| `reset_defaults` | PASS | 重置后恢复配置并重新应用 8 规则 |
| ZIP 构建/完整性 | PASS | 10,293,687 bytes；SHA256 见下 |
| `ksud module install` | PASS | 安装器识别 SukiSU；配置保留；生成 modules_update |
| 配置继承 | PASS | 升级保留 8 条；首次安装才导入旧 `susfs4ksu` |
| **冷启动自动加载** | **未验证** | 需要重启 + 临时 root 流程 |
| **真实 SukiSU WebUI** | **未验收** | 只做了本地 mock |
| **停用旧模块后复测** | **未验证** | 旧模块仍启用 |
| **Wild Detector 实验检测** | **未复测** | v24；当前未确认干净 |
| 其他分支实机 | 未测试 | 无设备；仅路径/fake 检测 |

---

## 2. 静态与宿主机测试

### 2.1 脚本语法

对以下脚本做过 `sh -n` 语法检查：

```text
common.sh
load.sh
apply.sh
ctl.sh
action.sh
customize.sh
post-fs-data.sh
boot-completed.sh
kmi.sh
```

结果：通过。  
注意：`sh -n` 只证明语法，不证明 Android toybox 下所有命令行为；已在设备上跑过主要路径。

### 2.2 WebUI 本地预览

- `webui_preview/` 使用 mock 数据在本地浏览器渲染。
- 浅色/深色两套 MIUIX 预览：
  - `preview_miuix_status_light.png`
  - `preview_miuix_config_light.png`
  - `preview_miuix_status3.png`
  - `preview_miuix_config3.png`
  - `preview_miuix_log3.png`
  - `preview_miuix_about3.png`
- 无外部 CDN；CSS/JS 本地。
- 页面标题、`rootManager`、`binPath`、`footerVersion` 等字段通过检查。
- **未在真实 SukiSU WebView 中打开验收。**

### 2.3 ZIP 校验

最终包：

```text
dist/susfs_allinone-1.1.0.zip
size: 10293687
sha256: 0633E4ED9A8507415E3A0DFCE9606C39B9ACCAFB7E9867C7D7FE3A35CC55F3A2
```

已检查：

- ZIP 可解压，`testzip` 无损坏。
- 必需文件存在：`module.prop`、`common.sh`、`load.sh`、`apply.sh`、`ctl.sh`、`action.sh`、`customize.sh`、`post-fs-data.sh`、`boot-completed.sh`、`webroot/index.html`、`webroot/app.js`、`webroot/style.css`。
- `module.prop` 名称/版本正确。
- 分支字符串存在。
- 入口脚本权限 0755。
- `common.sh` 为 0644。

接收方可重跑：

```powershell
python tools\check_zip.py .\dist\susfs_allinone-1.1.0.zip
```

---

## 3. 分支检测测试

使用 fake `pm` 输出验证 `ksu_branch()`：

| 模拟包名 | 结果 |
|---|---|
| `com.sukisu.ultra` | `SukiSU` |
| `com.resukisu` | `ReSukiSU` |
| `com.rifsxd.ksunext` | `KernelSU Next` |
| `me.weishu.kernelsu` | `KernelSU` |
| 无匹配但 `/data/adb/ksu` 存在 | `KernelSU 系列` |

说明：

- 这是通过替换 `pm` 输出做的逻辑验证，不是实机分支测试。
- 官方 KernelSU / ReSukiSU / KernelSU Next 的真实二进制路径、`ksu_susfs` 版本和 LKM 兼容性仍需实机确认。
- APatch 只验证了二进制发现路径；安装器不支持 APatch 安装。

---

## 4. 二进制回退测试

目标：确认活动分支二进制不可用时，不会误覆盖分支文件，且能回退到模块备份。

方法（设备已 root 的手动测试）：

```sh
SUSFS_BIN=/system/bin/false sh /data/adb/modules/susfs_allinone/apply.sh
```

预期/结果：

- `select_susfs_bin` 回退到 `/data/adb/modules/susfs_allinone/bin/ksu_susfs_good`。
- `apply.log` 记录 `ksu_susfs: .../bin/ksu_susfs_good`。
- 8 条 `sus_path` 规则成功。
- 备份二进制提示 `[-] Requires susfs v1.5.8+`；功能门提示，不是失败。
- 未覆盖 `/data/adb/ksu/bin/ksu_susfs`。

之后恢复正常配置并重新应用，`ctl status` 回到活动二进制，`rules=8`。

---

## 5. 手动加载/应用测试

### 5.1 Action

在 SukiSU 模块 Action / 等价命令执行：

```sh
sh /data/adb/modules/susfs_allinone/action.sh
```

结果：

- 输出管理器分支、LKM 已加载、`v2.3.0`、用户 `sus_path` 规则数、`kernelsu` 隐藏状态、`ksu_susfs` 路径。
- 规则数 8。
- 日志写入 `apply.log`。
- 不需要重启即可恢复规则（前提是 LKM 已加载或能加载）。

### 5.2 `post-fs-data.sh`

在 LKM 已存在的情况下手动执行，验证：

- 禁用/移除/safe mode/`disable_autoload` 检查。
- 读取 `auto_load=1`。
- 调用 `load.sh`；因为 LKM 已存在，走“跳过加载并验证通信”路径。

结果：通过。  
**注意：这不是冷启动验证。**

### 5.3 `boot-completed.sh`

在 LKM 已存在的情况下手动执行，验证：

- 读取 `auto_load=1`。
- 调用 `apply.sh`。
- 8 条规则成功，marker 正常。

结果：通过。  
**注意：没有验证 boot 阶段 `/sdcard/Android/data` 的真实时序。**

### 5.4 `reset_defaults`

通过 `ctl.sh reset_defaults` 重置配置：

- 默认 `auto_load=1`、`hide_sus_mnts=1`、`avc_spoof=0`、`replace_rules=1`。
- `sus_path.txt` 默认仅 `/data/adb`。
- `hide_modules.txt` 为 `kernelsu`。
- 删除 `disable_autoload`。

测试后从备份恢复原配置（8 条 `sus_path`）并重新 `apply.sh`，`ctl status` 恢复 `rules=8`。

---

## 6. 安装与配置继承测试

### 6.1 安装

使用：

```sh
ksud module install /sdcard/Download/susfs_allinone-1.1.0.zip
```

结果：

- 安装器识别当前管理器为 SukiSU。
- 选择 `android15-6.6` LKM。
- 保留已安装的 8 条 `sus_path` 和 `config.sh`。
- 生成 `/data/adb/modules_update/susfs_allinone`。
- `ksud module list` 显示 `susfs_allinone` 版本 1.1.0、`web=true`、`update=true`。
- 活动模块仍是旧活动副本；待重启/管理器合并。

### 6.2 配置继承逻辑

- 已安装 `/data/adb/modules/susfs_allinone/config/sus_path.txt` → 复制 5 个配置文件，保留现有配置。
- 首次安装且存在 `/data/adb/susfs4ksu/sus_path.txt` → 只导入 `sus_path`/`sus_mount`/`try_umount`，`hide_modules` 设为 `kernelsu`。
- 测试中 8 条规则被保留，没有发生覆盖。

### 6.3 当前状态

`device_snapshot/status.txt`：

```text
module_version=1.1.0
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
```

待合并更新仍在，`update=true` 预期。

---

## 7. 当前未测试/不能声称通过

1. **冷启动**：没有在“重启 + 临时 root”后看到新的 `load.log`/`apply.log`，所以不能声称 `post-fs-data`/`boot-completed` 自动链路通过。
2. **真实 WebUI**：没有在 SukiSU 的 WebView 中打开；mock 预览不代表后端/权限/文件选择器正常。
3. **停旧模块后**：`susfs4ksu`/`susfs_oneshot` 仍启用；未验证停用后规则是否仍为 8、是否出现重复/回退。
4. **Wild Detector**：未在实验检测开启时复测；不能声称“干净”。
5. **其他分支**：没有官方 KernelSU/ReSukiSU/KernelSU Next 实机；分支兼容性目前是路径/fake 逻辑验证。
6. **其他 KMI**：只验证了 `android15-6.6` 当前设备；其他 7 个 KMI 的 LKM 未实机加载。
7. **APatch 安装**：未支持，只做二进制发现。

---

## 8. 预跑记录

`device_snapshot/verify_after_boot_current.txt` 是在重启前运行 `tools/verify_after_boot.sh` 的原始记录（2026-10-20 21:56）。因为 `modules_update` 仍存在，脚本按设计输出：

```text
FAIL: pending update still exists at /data/adb/modules_update/susfs_allinone
VERIFY_RESULT=FAIL
```

其余检查（`lkm_present=1`、`rules=8`、`auto_load=1`、`ksu_bin=ok`、marker、17 行路径）均正常。这个 `FAIL` 是预跑预期，不代表冷启动失败；重启并合并更新后应变为 `OK`。

注意：部分 adb/Windows 组合不传回远程退出码，判断以 `VERIFY_RESULT` 行/文本为准。

## 9. 复验命令

```powershell
# 只读设备快照
python tools\capture_device_snapshot.py

# ZIP 校验
python tools\check_zip.py .\dist\susfs_allinone-1.1.0.zip

# 冷启动（设备上）
adb push tools\verify_after_boot.sh /data/local/tmp/verify_after_boot.sh
adb shell sh /data/local/tmp/verify_after_boot.sh 8
```

`verify_after_boot.sh` 会检查：

- `lkm_present=1`
- `rules=8`
- `auto_load=1`
- `ksu_bin=ok`
- `root_manager` 非 `Unknown`
- `/proc/susfs_path` 有路径
- marker 存在
- `modules_update` 已消失
- 输出旧模块启用状态（仅提示，不自动禁用）

任何一项失败，先保存输出和日志，不要执行 `rmmod`。