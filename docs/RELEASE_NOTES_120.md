## 1.2.0

### 修复

- **Scene 隐藏失效**：Scene 每次重启会在 `/dev` 下重建随机名目录，旧实现只在 apply 时扫一次，晚于 apply 启动或重启换名后就漏掉。现在：
  - `apply.sh` 内最多三轮扫描（0s / 5s / 10s），命中即停；
  - 新增 `ctl.sh rescan_scene`，可随时补扫；
  - WebUI「隐藏 Scene 痕迹」下方新增「重扫 Scene」按钮。
- **成功被误报为失败**：`rescan_scene` / `guard_status` 结尾的判断语句返回 1，导致 WebUI 把 `hidden /dev/xxx` 当成错误弹出。已改为 `exit 0`。
- **「重扫 Scene」按钮排版**：按钮与说明被强制换行、多画一条分隔线，已改为同一行、说明占剩余宽度。

### 新增

- **自动 try_umount（模块挂载）**：读取 `/proc/1/mountinfo`，识别 KSU overlay（源为 `KSU`）与 bind 自 `/data/adb` 的挂载（依据挂载根字段含 `/adb/`），自动加入卸载列表，不必手写路径。
- **跳过系统正常挂载**：过滤 `erofs`/`ext4`/`f2fs`/`squashfs`/`vfat` 且挂载根为 `/` 的真实分区，避免误卸。

说明：本机 LKM 未启用 `CONFIG_KSU_SUSFS_TRY_UMOUNT`，两个开关会明确跳过并写日志；上游内核支持该特性时才会真正生效。

- **移除「强制隐藏 LSPosed」与 ksud 全局挂载登记**：该功能会把 `/proc/1/mountinfo` 中所有来源含 `/adb/`、或来源为 `KSU`/`shared` 的挂载登记进 KernelSU 全局卸载列表，范围不限于 LSPosed，可能影响其他隐藏模块与应用看到的挂载视图。相关开关、`ctl.sh register_lsposed_mounts`、`ctl.sh wipe_umount` 一并移除。
- **跳过隐藏列表改为可配置**：原先写死 `duckdetector` / `appvisibility` / `nativecheck` 三个包名，现在改为读 `config/skip_hide.txt`（每行一个子串，支持 `#` 注释），安装升级时保留用户编辑。
- **风险开关加提示**：`伪装 CMDLINE` 与 `VOLD 隔离` 在 WebUI 中补上说明——改写启动参数可能被检测工具判为异常，隐藏 `Android/data`/`Android/obb` 可能导致应用读不到自己的外部存储。
- **自动 try_umount 收紧**：默认关闭；开启后**始终**过滤真实分区（`erofs/ext4/f2fs/squashfs/vfat` 且根为 `/`），该保护不再可通过配置关闭；登记成功的挂载会写入 `state/try_umount_auto.txt`，便于排查。
- **不再改写管理器目录下的 ksu_susfs**：管理器自带的二进制无法执行时，以前会把模块备份复制成 `ksu_susfs` 并留下 `.mod-broken`，等于修改模块以外的文件。现在只在本次运行改用模块备份，不写盘。
- **能力判定改为只读**：以前用真实的 `add_sus_mount` / `add_try_umount` 调用做探测，`rmdir` 只删目录并不注销规则；而且路径不存在时客户端会先报 `Failed to stat`，根本到不了内核，导致把不支持误判为支持（真机实测：内核日志有 `unsupported cmd 0x55560`，探测却返回可用）。现在只读 `show enabled_features` 判定，真正调用失败时再降级为不支持并记录来源。
- **开机只执行一次 apply**：1.2.0 原本会在开机 45 秒后再补跑一次 `apply.sh`（等应用数据目录就绪），等于在系统运行中再清理并重建一次 `sus_path` 规则。现恢复为每次开机只执行一次；开机早期还不存在的应用数据目录不会被重试，需要时在 WebUI 点「加载并应用」补一次即可。
- **sus_path 清理改为只删自己的规则**：旧实现 `replace_rules=1` 会向 `/proc/susfs_path` 写 `clear`，把其他隐藏模块写入的规则一起清掉；1.2.0 又增加了开机 45 秒后的补应用，等于在系统运行中再清一次。现在：
  - `replace_rules=1` 只逐条删除 `state/our_paths.txt` 里记录的、本模块自己写过的路径；
  - 首次升级没有清单时，按 `sus_path.txt` 中声明的路径逐条删除（只动配置内路径）；
  - `replace_rules=2` 才是整表 `clear`，需显式配置；
  - 真机验证：首次迁移删 9 条、二次 apply 删 12 条，均 `失败 0`；LKM 自身的 `/proc/susfs_*` 规则未被清除。
- **选择 KMI 改用真实内核**：`/proc/sys/kernel/osrelease` 可能被本模块的 uname 伪装改写，直接用它匹配会在伪装开启时选错 `.ko`（真机出现过 6.12 内核选中 `android15-6.6`）。现在按 `/proc/version`、`state/real_uname.txt`、osrelease 的优先级取真实 release，并在检测到伪装时写日志说明。

### 诊断与自愈

- **`ctl.sh caps`**：一次列出 LKM 能力位（sus_mount / try_umount / open_redirect 等）、取值来源（特性位 / proc 节点 / 实测降级）与降级标记，便于判断"为什么某项没生效"\
- **`ctl.sh compat`**：检查模块与当前管理器 / 内核的兼容性（ELF 架构、KernelSU 分支识别、LKM 是否已加载、KMI 匹配结果）\
- **`ctl.sh diag`**：一次输出内核/KMI/LKM 状态、两个 `ksu_susfs` 二进制的 `show version`/`variant`/`features`（带 rc 与原始输出）、dmesg 相关行、日志尾部。
- **坏二进制只回退不替换**：管理器自带的 `ksu_susfs` 若无法执行（架构不符/文件损坏），本次运行改用模块内置备份，不向管理器目录写任何文件。
- **ELF 架构识别**：`elf_machine()` 读 ELF 头判断 `aarch64` / `x86_64` / `arm` / `x86` / `not-elf`。
- **能力探测加固**：探测前先确认二进制可执行；输出含 `Exec format error` / `cannot execute` / `Failed to stat` / `No such file` 一律判为不可用。
- **`tools/susfs_diag.sh`**：独立诊断脚本，`su -c "sh /sdcard/Download/susfs_diag.sh"`，结果写入 txt。

### 调整

- 预设隐藏项不再收录随机命名的 Scene 目录（重启即失效，只会留下死规则），改由开关 + 重扫统一处理。

### 沿用 1.1.9

- 启动守卫（防重启循环，覆盖 late-load）
- BL 解锁检测与仅解锁可用的两项隐藏
- GAPPS / DEX2OAT / Scene 隐藏开关
- 预设隐藏项弹窗（三态全选）
- BakaSU 与 ReSukiSU 包名冲突的显示处理（组合名 + `manager_name` 覆盖）
- WebUI 保存失败（`managerName is not defined`）已修复

### 验证

- 真机确认 Scene 目录名已变化（`/dev/zrjngor_` → `/dev/mzcfqbvj`），重扫后成功隐藏
- 人造目录 `/dev/scenetest_zz` 测试：`rescan_scene` 正确识别并隐藏，`/proc/susfs_path` 出现对应规则
- `rescan_scene` / `guard_status` 退出码实测均为 0
### 安全与架构

- **配置改为 `config.ini` 纯数据格式**：配置不再被 `source`，由 `cfg_load` 逐行解析成变量，命令注入 / 环境变量劫持 / 路径覆盖整类风险消失。旧 `config.sh` 在安装期（`customize.sh`）与运行时（`cfg_migrate`）两条路径自动迁移，原文件保留为 `config.sh.bak`。
- **WebUI 保存合并为一次 `set_bundle`**：config 与 5 个规则文件一次提交，config 校验不通过则整体不落盘；保存从 6 次后端调用降为 1 次，apply 读到「新配置 + 旧规则」的窗口从毫秒级压到微秒级。
- **`sus_mount` / `try_umount` 按开机去重**：内核没有查询接口，改为模块侧按 `boot_id` 记账（`state/*_added.txt`），失败不记账、下次重试，避免重复 apply 让内核列表膨胀。
- **状态页「手动确认 BL 已解锁」开关**：针对伪回锁设备（属性显示 locked 但实际已解锁）。标记写入独立文件 `state/force_bl_unlocked`，**不放进 `config.ini`**——通用配置写入命令无法绕过前端的 10 秒确认；关闭开关即恢复读取系统属性。
- **后端写入范围收紧**：`ctl.sh` 固定模块路径，不再接受环境传入的 `MODDIR`/`CONFIG`/`STATE`；配置校验拒绝保留键与重复键；`set_config`/`set_bundle` 也无法改写 BL 标记。
- **关于页**：贡献者卡片增加滚动触发动效，感谢 `@hhgbmh8-ux` 的真机测试与问题复现。

### 测试

13 个离线测试（配置迁移、校验、bundle、锁、路径、挂载去重、BL 覆盖、KMI 选择、分区过滤、WebUI 合并等）已接入 GitHub Actions，每次构建前自动执行。