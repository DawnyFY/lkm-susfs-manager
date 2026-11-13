// SPDX-License-Identifier: GPL-2.0-only
// 轻量英文本地化：默认跟随系统语言，可在「关于」页切换（切换后重载页面）。
// 静态文案由 walk() 翻译；脚本动态插入的节点由 MutationObserver 补翻；
// 脚本拼出的整段提示在 app.js 里调用 i18n.tl() 翻译，避免先闪一下中文。
(function () {
  "use strict";

  var DICT = {
    /* ---------- 通用 / 导航 ---------- */
    "LKM SUSFS管理器": "LKM SUSFS Manager",
    "自动匹配内核 · 一键加载 · 规则管理": "Auto-detect kernel · One-tap load · Rule management",
    "检测中": "Checking",
    "状态": "Status",
    "导出日志": "Export logs",
    "导出失败": "Export failed",
    "日志已导出：%s": "Logs exported: %s",
    "配置": "Config",
    "日志": "Logs",
    "关于": "About",
    "读取中…": "Loading…",
    "加载中…": "Loading…",
    "加载并应用": "Load & apply",
    "仅应用配置": "Apply only",
    "保存并应用": "Save & apply",
    "刷新": "Refresh",
    "恢复默认": "Restore defaults",
    "取消": "Cancel",
    "确定": "OK",
    "确认操作": "Confirm action",
    "我知道了": "Got it",
    "中文": "Chinese",
    "语言 / Language": "Language",
    "追加所选": "Add selected",
    "全选": "Select all",
    "。": ".",
    "暂无日志。": "No logs yet.",
    "运行日志": "Runtime log",

    /* ---------- 状态页 ---------- */
    "当前内核": "Current kernel",
    "LKM 状态": "LKM status",
    "sus_path 规则": "sus_path rules",
    "kernelsu 隐藏": "KernelSU hidden",
    "自动加载": "Auto load",
    "手动确认 BL 已解锁": "Confirm BL unlocked",
    "管理器": "Manager",
    "LKM 变体": "LKM variant",
    "ksu_susfs 路径": "ksu_susfs path",
    "WebUI 标记": "WebUI marker",
    "连续失败次数": "Consecutive failures",
    "模块版本": "Module version",
    "运行中": "Running",
    "未加载": "Not loaded",
    "已加载": "Loaded",
    "命令失败 (": "Command failed (",
    "内置": "Built-in",
    "内置 SUSFS": "Built-in SUSFS",
    "加载完成，但部分规则失败；详情见日志。": "Load finished, but some rules failed; see the log.",
    "部分规则失败，详情见日志": "Some rules failed; see the log",
    "配置已应用，但部分规则失败；详情见日志。": "Config applied, but some rules failed; see the log.",
    "配置已保存并应用，但部分规则失败；详情见日志。": "Config saved and applied, but some rules failed; see the log.",
    "已隐藏": "Hidden",
    "未隐藏": "Not hidden",
    "开启": "On",
    "关闭": "Off",
    "正常": "OK",
    "不兼容": "Incompatible",
    "缺失": "Missing",
    "已创建": "Created",
    "未创建": "Not created",
    "未知内核": "Unknown kernel",
    "模块版本未知": "Module version unknown",
    "模块 v%s": "Module v%s",
    "模块 v1.1.0": "Module v1.1.0",
    "LKM：inforcqb/susfs4ksu-lkm": "LKM: inforcqb/susfs4ksu-lkm",
    "：": ":",

    /* ---------- 配置页 ---------- */
    "开关": "Switches",
    "预设隐藏项": "Preset hidden items",
    "开机自动加载并应用": "Load and apply on boot",
    "隐藏 SUS 挂载点（非 root 进程）": "Hide SUS mount points (non-root)",
    "AVC 日志伪装": "AVC log spoofing",
    "应用时清理本模块上次写入的 sus_path 规则": "Clear this module's sus_path rules from the previous run when applying",
    "隐藏 KSU LOOP 挂载": "Hide KSU LOOP mounts",
    "隐藏 REVANCED / YouTube 模块路径": "Hide REVANCED / YouTube module paths",
    "隐藏自定义 ROM 路径": "Hide custom ROM paths",
    "隐藏 COMPAT MATRIX": "Hide COMPAT MATRIX",
    "隐藏 GAPPS": "Hide GAPPS",
    "强制隐藏 DEX2OAT 挂载": "Force hide DEX2OAT mounts",
    "隐藏 Scene 痕迹": "Hide Scene traces",
    "重扫 Scene": "Rescan Scene",
    "开过 Scene 后点一下，把新目录补进隐藏列表": "Tap after using Scene to add new directories to the hidden list",
    "自动 try_umount（模块挂载）": "Auto try_umount (module mounts)",
    "扫描 /proc/1/mountinfo，把来源在 /data/adb 下的挂载加入卸载列表，不用手写路径。": "Scans /proc/1/mountinfo and adds mounts sourced under /data/adb to the unmount list; no manual paths needed.",
    "过滤真实系统分区（始终开启）": "Filter real system partitions (always on)",
    "开启上一项后，erofs/ext4/f2fs/squashfs/vfat 且根挂载为 / 的真实分区一律跳过，避免误卸系统分区。": "With the item above on, real partitions (erofs/ext4/f2fs/squashfs/vfat mounted at /) are skipped so system partitions are never unmounted by mistake.",
    "不隐藏检测类应用的数据目录": "Keep detection apps' data dirs visible",
    "命中列表见": "Matched list: see",
    "。隐藏检测工具自身目录可能反而让它判定异常。": ". Hiding a detector's own directory may make it flag the device as abnormal.",
    "伪装 CMDLINE": "Spoof CMDLINE",
    "CMDLINE 伪装内容": "CMDLINE spoof value",
    "伪装后内核读到的 cmdline 内容；留空则不下发。": "The cmdline the kernel will read after spoofing; leave empty to skip.",
    "注意：改写启动参数可能被部分检测工具判为异常（例如启动参数痕迹），不确定时保持关闭。": "Note: rewriting boot arguments may be flagged by some detectors (boot-arg traces). Keep it off if unsure.",
    "强制指定 KMI": "Force KMI",
    "自动匹配（推荐）": "Auto match (recommended)",
    "只在自动匹配失败时用。选项会自动列出本模块实际打包的 KMI，选错也不会加载不存在的文件。": "Use only when auto match fails. Options list the KMIs actually bundled with this module, so a wrong pick cannot load a missing file.",
    "伪装内核版本（uname）": "Spoof kernel version (uname)",
    "只影响用户态看到的版本，不能用来跨版本加载 .ko。": "Only affects what userspace sees; it cannot load a .ko across kernel versions.",
    "内核 release": "Kernel release",
    "内核 version": "Kernel version",
    "伪装后的 uname -r 内容；留空则传 default。开机时的真实值已记在 state/real_uname.txt。": "Spoofed uname -r value; empty sends default. The real value at boot is recorded in state/real_uname.txt.",
    "伪装后的 uname -v 内容；留空则传 default。填错可用 ctl.sh restore_uname 还原。": "Spoofed uname -v value; empty sends default. If wrong, restore with ctl.sh restore_uname.",
    "隐藏 VENDOR SEPOLICY": "Hide VENDOR SEPOLICY",
    "仅解锁 BL 可用。临时 root 下这些文件早在开机早期被读过，隐藏无效，会明确跳过。": "Unlocked BL only. Under temp root these files are read early at boot, so hiding has no effect and is skipped explicitly.",
    "模拟 VOLD 应用数据隔离": "Simulate VOLD app data isolation",
    "仅解锁 BL 可用。把 Android/data、Android/obb 从可见路径里藏掉，模拟分区隔离。": "Unlocked BL only. Hides Android/data and Android/obb from visible paths to simulate partition isolation.",
    "注意：部分应用会因此读不到自己的外部存储，出现异常时先关闭本项。": "Note: some apps may then fail to read their own external storage; turn this off first if something breaks.",
    "关闭自动加载后，仍可在“状态”页手动加载。AVC 伪装默认关闭。“清空旧规则”打开时，删除路径会立即生效；如果还有其他模块也在管理 sus_path，请关闭它。": "With auto load off you can still load manually from Status. AVC spoofing is off by default. With “clear old rules” on, removed paths take effect immediately; turn it off if other modules also manage sus_path.",
    "下面五项只隐藏实际存在的路径，默认全关，开启前请确认你确实需要。它们只影响隐藏可见性，不参与开机流程，所以在临时 root（late-load）环境下同样安全；但会让某些检测类应用看不到对应文件，自行权衡。": "The five items below only hide paths that really exist and are all off by default. They affect visibility only and are not part of the boot flow, so they are equally safe under temp root (late-load); they do hide those files from some detector apps, so weigh the trade-off.",
    "隐藏路径": "Hidden paths",
    "每行一个路径，支持": "One path per line; supports ",
    "注释。建议保留": "comments. Keep ",
    "；隐藏后 SukiSU 与本 WebUI 仍可正常使用。保存时是否先清空旧规则，由上方“清空旧规则”开关决定。": "; SukiSU and this WebUI keep working after hiding. Whether to clear old rules first is controlled by the switch above.",
    "隐藏模块名": "Hidden module names",
    "延迟路径": "Deferred paths",
    "注释。路径可以暂不存在；内核会保存规则并有界重试解析，路径出现后自动隐藏。适合会被删除后重建的目录。需要内核支持": "comments. The path may not exist yet; the kernel stores the rule and retries resolution within a bound, then hides it once it appears. Useful for directories that are deleted and recreated. Requires kernel support for",
    "；不支持的设备会在 apply.log 明确报错。": "; unsupported devices report an explicit error in apply.log.",
    "# 例如 /data/adb/modules/某模块/新建目录": "# e.g. /data/adb/modules/some_module/new_dir",
    "每行一个模块名，写入": "One module name per line, written to ",
    "。LKM 会自动隐藏自己，这里通常只需要": ". The LKM hides itself, so normally only ",
    "不隐藏的包名": "Packages not hidden",
    "每行一个包名或路径片段（子串匹配，支持": "One package name or path fragment per line (substring match; supports ",
    '注释）。命中这里的应用不会被隐藏其数据目录；检测类工具通常需要加进来，否则它可能把"看不见自己"判为异常。': "comments). Apps listed here keep their data dirs visible; detector tools usually need to be added, or they may treat “cannot see itself” as abnormal.",
    "高级：sus_mount / try_umount": "Advanced: sus_mount / try_umount",
    "sus_map（mmap 隐藏）": "sus_map (mmap hiding)",
    "当前设备通常无需填写。sus_mount 每行一个": "Usually not needed on current devices. sus_mount takes one ",
    "挂载前缀": "mount prefix",
    "（写入": "(written to",
    "，上限 64 条）；旧内核会回退到逐条": ", limit 64); older kernels fall back to per-entry",
    "。try_umount 每行一个路径。都支持": ". try_umount takes one path per line. All support",
    "注释。sus_map 写入": "comments. sus_map is written to",
    "，隐藏进程": ", hiding",
    "里的真实文件路径（需 LKM r18.5+）。": "real file paths inside processes (requires LKM r18.5+).",
    "导入旧 susfs4ksu 配置": "Import old susfs4ksu config",

    /* ---------- BL 确认块 ---------- */
    "仅用于": "For ",
    "伪回锁": "fake-locked",
    "设备（BL 实际已解锁，但": " devices only (BL is actually unlocked, but",
    "被伪装成 locked）。": "is spoofed as locked).",
    "打开后模块会永久记住「已解锁」，允许执行": "Once enabled, the module permanently remembers “unlocked” and allows ",
    "隐藏 vendor sepolicy": "hiding vendor sepolicy",
    "与": " and ",
    "VOLD 隔离": "VOLD isolation",
    "； 这两项会改变系统可见状态，": "; both change visible system state, ",
    "可能导致应用读不到自己的外部存储": "and may cause apps to lose access to their external storage",
    "。确认设备确实已解锁 BL 再开启。": ". Enable only if the device really is BL-unlocked.",

    /* ---------- 关于页 ---------- */
    "把 LKM 自动匹配、加载、规则配置和 WebUI 收进同一个模块。": "Auto KMI matching, LKM loading, rule config and the WebUI in a single module.",
    "支持 8 种 GKI KMI：android12-5.10 到 android17-6.18": "8 GKI KMIs supported: android12-5.10 through android17-6.18",
    "兼容 KernelSU / SukiSU / ReSukiSU / KernelSU Next / Magisk": "Works with KernelSU / SukiSU / ReSukiSU / KernelSU Next / Magisk",
    "兼容管理器：KernelSU 官方版、SukiSU、ReSukiSU、KernelSU Next、Magisk；APatch 已做安装识别与阶段适配，未实机验证": "Managers: KernelSU, SukiSU, ReSukiSU, KernelSU Next, Magisk; APatch is recognized and wired for its boot stages, but not yet verified on a real device",
    "按管理器选择开机阶段：KernelSU 系列与 APatch 走 post-fs-data → boot-completed，Magisk 走 post-fs-data → service（late_start）": "Boot stages follow the manager: KernelSU series and APatch run post-fs-data → boot-completed, Magisk runs post-fs-data → service (late_start)",
    "APatch：需要内核已集成 SUSFS 或允许加载 SUSFS LKM；WebUI 需第三方宿主（如 KsuWebUI）": "APatch: requires a kernel with SUSFS built in or able to load the SUSFS LKM; the WebUI needs a third-party host (e.g. KsuWebUI)",
    "APatch / KernelPatch 共存模式：检测到 kpimg 时自动关闭 avc_spoof（与它的 SELinux hook 重叠），路径/挂载隐藏不受影响": "APatch / KernelPatch coexist mode: when kpimg is detected, avc_spoof is disabled automatically (it overlaps kpimg’s SELinux hooks); path and mount hiding are unaffected",
    "APatch 防护：默认不自动外挂 SUSFS LKM（需 ctl.sh allow_lkm 显式放行）；检测到上次启动 SUSFS 相关 panic/oops 会自动暂停自动加载": "APatch protection: the SUSFS LKM is not auto-loaded by default (run ctl.sh allow_lkm to opt in); if the previous boot showed a SUSFS-related panic/oops, auto-load is paused",
    "⚠️ APatch：默认不加载 SUSFS LKM（共存风险）；内置 SUSFS 或 ctl.sh allow_lkm": "⚠️ APatch: SUSFS LKM is not loaded by default (coexistence risk); use built-in SUSFS or run ctl.sh allow_lkm",
    "⚠️ APatch：手动外挂需先 ctl.sh allow_lkm": "⚠️ APatch: manual LKM loading is blocked; run ctl.sh allow_lkm first",
    "❌ 上次启动疑似 SUSFS 崩溃，已暂停自动加载（ctl.sh resume_autoload）": "❌ The previous boot looked like a SUSFS crash; auto-load is paused (ctl.sh resume_autoload)",
    "⚠️ 自动加载已暂停（ctl.sh resume_autoload 恢复）": "⚠️ Auto-load is paused (ctl.sh resume_autoload to resume)",
    "❌ 内核已禁止模块加载（modules_disabled=1），请使用内置 SUSFS 的内核": "❌ Kernel module loading is disabled (modules_disabled=1); use a kernel with built-in SUSFS",
    "❌ 内核未编译 CONFIG_MODULES，无法加载 SUSFS LKM": "❌ Kernel was built without CONFIG_MODULES; the SUSFS LKM cannot be loaded",
    "WebUI 支持中文 / English": "WebUI in Chinese / English",
    "开机时 post-fs-data 先取真实内核版本（优先 /proc/version，回退 state/real_uname.txt），从模块自带的 8 个 KMI 中选出匹配的 LKM 并加载；随后按管理器应用规则：KernelSU 系列在 boot-completed 阶段，Magisk 在 service（late_start）阶段设置 sdcard 根路径并应用规则。热重启不会卸载 LKM，冷重启后会自动重新加载。": "On boot, post-fs-data reads the real kernel version first (prefers /proc/version, falls back to state/real_uname.txt), then picks and loads the matching LKM from the 8 bundled KMIs. Rules are then applied per manager: KernelSU series on boot-completed, Magisk on service (late_start), which also sets the sdcard root. A hot reboot keeps the LKM loaded; after a cold reboot it reloads automatically.",
    "自动寻找当前管理器的 ksu_susfs，失败时回退模块备份": "Finds the current manager's ksu_susfs automatically, falling back to the bundled copy",
    "Loader：susfs_insmod（自动解析符号与 vermagic）": "Loader: susfs_insmod (resolves symbols and vermagic)",
    "不要执行": "Do not run ",
    "。已知存在 UAF/panic 风险。热重启不会卸载 LKM；冷重启后由本模块重新加载。": ". Known UAF/panic risk. A hot reboot keeps the LKM loaded; after a cold reboot this module loads it again.",
    "自动加载带 KMI 校验和失败日志。内核更新后如果 KMI 不在支持列表，模块会拒绝加载并给出提示，不会强行注入。": "Auto load validates the KMI and logs failures. If a kernel update leaves no supported KMI, the module refuses to load and tells you instead of forcing injection.",
    "工作方式": "How it works",
    "开机时": "On boot,",
    "先取真实内核版本（优先": "reads the real kernel version first (prefers",
    "，回退": ", falls back to",
    "），从模块自带的 8 个 KMI 中选出匹配的 LKM 并加载；": "), then selects and loads the matching LKM from the 8 bundled KMIs; ",
    "再设置 sdcard 根路径并应用规则。热重启不会卸载 LKM，冷重启后会自动重新加载。": " then sets the sdcard root and applies rules. A hot reboot keeps the LKM loaded; after a cold reboot it reloads automatically.",
    "贡献者": "Contributors",
    "1.2.0 版本主要测试贡献者：强制隐藏 LSPosed 等多处问题由他的真机测试发现，后续修复也都经过他的复现与验证。": "Main tester for 1.2.0: several issues (e.g. force-hiding LSPosed) were found in his on-device tests, and later fixes were reproduced and verified by him.",
    "头像与昵称由贡献者本人提供。": "Avatar and nickname provided by the contributor.",

    /* ---------- 弹窗 / 横幅 ---------- */
    "⚠️ 模块文件已被修改": "⚠️ Module files were modified",
    "检测到模块内部文件与发布包不一致，当前安装的版本可能被改动过。": "Files inside the module do not match the release package; the installed version may have been modified.",
    "如果不是你自己修改的，建议从官方仓库重新下载安装。": "If you did not modify it yourself, reinstall from the official repository.",
    "按当前设备实际存在的目录列出，勾选后追加到 sus_path。已存在的项会标记出来。": "Lists directories that exist on this device; checked items are appended to sus_path. Existing entries are marked.",
    "当前页面不在 SukiSU WebUI 中运行": "This page is not running inside the SukiSU WebUI",
    "请在 SukiSU 的 WebUI 中打开本页面。": "Open this page in the SukiSU WebUI.",
    "无法连接 root 通道。": "Cannot connect to the root channel.",
    "命令超时（90 秒）": "Command timed out (90s)",
    "命令失败 (%s)": "Command failed (%s)",
    "初始化失败：%s": "Initialization failed: %s",
    "操作失败：%s": "Operation failed: %s",
    "操作失败": "Operation failed",
    "处理中…": "Working…",
    "请等待 %ss": "Please wait %ss",
    "我已了解风险，继续": "I understand the risk, continue",
    "规则文件读取失败，已禁用保存以免覆盖现有内容": "Failed to read rule files; saving is disabled to avoid overwriting existing content",
    "规则文件未成功读取，已阻止保存": "Rule files were not read successfully; saving blocked",
    "读取日志失败：%s": "Failed to read the log: %s",
    "写入失败：": "Write failed:",
    "⚠️ 当前 replace_rules=2：每次应用都会清空整张 sus_path 表（含其他模块的规则）": "⚠️ replace_rules=2: every apply clears the whole sus_path table (including other modules' rules)",
    "⚠️ 确认 BL 已解锁": "⚠️ Confirm BL is unlocked",
    "打开后模块会永久记住「BL 已解锁」，并允许执行 vendor sepolicy 隐藏与 VOLD 隔离。": "Once enabled, the module permanently remembers “BL unlocked” and allows vendor sepolicy hiding and VOLD isolation.",
    "这两项会改变系统可见状态：应用可能读不到自己的 Android/data，出现异常时需关闭本开关并重新应用配置。": "Both change visible system state: apps may fail to read their own Android/data; if something breaks, turn this off and reapply the config.",
    "只在你确认设备确实已解锁 bootloader（伪回锁）时继续。": "Continue only if you are sure the bootloader is really unlocked (fake relock).",
    "已写入配置并应用：BL 视为已解锁": "Written and applied: BL treated as unlocked",
    "已关闭手动解锁标记，BL 判定恢复为读取系统属性": "Manual unlock flag cleared; BL state is read from system properties again",
    "状态已刷新。": "Status refreshed.",
    "检测到上次加载 LKM 后设备未能完成启动，已自动暂停加载。": "The last boot after loading the LKM did not complete, so auto load was paused.",
    "要继续自动加载吗？如果上次是加载了不匹配的 .ko 导致重启，请先到「配置」页选对 KMI。": "Resume auto load? If the last reboot was caused by a mismatched .ko, set the right KMI on the Config page first.",
    "已恢复自动加载。下次开机会重新尝试。": "Auto load resumed; it will retry on the next boot.",
    "已恢复自动加载": "Auto load resumed",
    "恢复失败：%s": "Restore failed: %s",
    "LKM 未正常加载": "LKM did not load properly",
    "LKM 未加载。": "LKM is not loaded.",
    "LKM 未加载，日志里没有明确原因。": "LKM is not loaded; the log shows no clear reason.",
    "没有匹配当前内核的 KMI，LKM 未加载。": "No KMI matches the current kernel; LKM not loaded.",
    "匹配到了 .ko，但 insmod 返回错误，加载失败。": "A .ko matched but insmod returned an error; loading failed.",
    "当前内核: %s": "Current kernel: %s",
    "日志原因: %s": "Log reason: %s",
    "累计失败次数: %s": "Total failures: %s",
    "怎么处理:": "How to fix:",
    "1. 到「配置」页，把「强制指定 KMI」选成对应版本": "1. On the Config page, set Force KMI to the matching version",
    "2. 保存后点「加载并应用」": "2. Save, then tap Load & apply",
    "3. 仍失败就把「日志」页的 load.log 发给作者": "3. If it still fails, send load.log from the Logs page to the author",
    "1. 先在管理器里禁用本模块，重启确认能正常开机": "1. Disable this module in the manager first, then reboot to confirm the device still boots",
    "2. 把 load.log 内容反馈给作者，不要反复重试": "2. Report load.log to the author; do not retry repeatedly",
    "读取预设失败：%s": "Failed to read presets: %s",
    "重扫失败：%s": "Rescan failed: %s",
    "（已在列表）": "(in list)",
    "（未发现）": "(not found)",
    "（没有可追加的项）": "(nothing to add)",
    "（未打包）": "(not bundled)",
    "没有需要追加的项": "Nothing to add",
    "已追加 %s 项，记得点保存": "Added %s item(s); remember to save",
    "已补充隐藏 %s 项：": "Added %s hidden item(s):",
    "没有发现新的 Scene 痕迹。": "No new Scene traces found.",
    "正在加载 LKM 并应用配置…": "Loading the LKM and applying config…",
    "正在应用配置…": "Applying config…",
    "正在保存并应用…": "Saving and applying…",
    "正在导入旧配置…": "Importing old config…",
    "正在恢复默认…": "Restoring defaults…",
    "加载并应用完成。": "Load & apply finished.",
    "加载并应用完成": "Load & apply finished",
    "配置已应用。": "Config applied.",
    "配置已应用": "Config applied",
    "配置已保存并应用。": "Config saved and applied.",
    "配置已保存并应用": "Config saved and applied",
    "导入旧 susfs4ksu 配置会覆盖当前的 sus_path / sus_mount / try_umount，继续？": "Importing an old susfs4ksu config overwrites the current sus_path / sus_mount / try_umount. Continue?",
    "旧配置已导入。检查后点“保存并应用”即可生效。": "Old config imported. Review it, then tap “Save & apply”.",
    "旧配置已导入": "Old config imported",
    "恢复默认会覆盖当前所有规则配置，继续？": "Restoring defaults overwrites all current rule config. Continue?",
    "已恢复默认配置。点“保存并应用”可立即生效。": "Defaults restored. Tap “Save & apply” to take effect.",
    "已恢复默认": "Defaults restored",

    /* ---------- 模块描述（apply.sh / load.sh 写入 module.prop） ---------- */
    "自动匹配 8 种 KMI；兼容 KernelSU 系列 / Magisk；含 WebUI 与规则管理": "Auto-match 8 KMIs; KernelSU series / Magisk; includes WebUI and rule management",
    "✅ 运行中 | %s 条规则 | %s | %s": "✅ Running | %s rules | %s | %s",
    "⚠️ 自动加载已暂停（上次启动未完成），请检查 KMI 后手动加载": "⚠️ Auto load paused (last boot did not finish); check the KMI and load manually",
    "❌ LKM 加载失败，请查看日志": "❌ LKM failed to load; check the log",
    "❌ ksu_susfs 缺失": "❌ ksu_susfs missing",
    "❌ ksu_susfs 无法通信": "❌ ksu_susfs cannot communicate",
    "⚠️ 自动加载已暂停，请在 WebUI 恢复": "⚠️ Auto load paused; resume it in the WebUI",
    "⚠️ LKM 已加载，但 ksu_susfs 无法通信": "⚠️ LKM loaded but ksu_susfs cannot communicate",
    "✅ LKM 已加载 | %s | 等待应用规则": "✅ LKM loaded | %s | waiting to apply rules",
    "⚠️ 未匹配内核 | %s | 请在 WebUI 指定 KMI": "⚠️ No kernel match | %s | set the KMI in the WebUI",
    "✅ LKM 已加载 | %s | %s": "✅ LKM loaded | %s | %s",
    "❌ APatch: 未找到 SUSFS 接口（内核需集成 SUSFS 或允许加载 SUSFS LKM）": "❌ APatch: SUSFS interface not found (kernel must include SUSFS or allow loading the SUSFS LKM)",
    "❌ APatch: SUSFS 接口无响应（内核 SUSFS 版本可能不匹配）": "❌ APatch: SUSFS interface not responding (kernel SUSFS version may mismatch)",
    "❌ APatch: LKM 加载失败（内核可能禁止 insmod 或符号不匹配）": "❌ APatch: LKM failed to load (kernel may reject insmod or symbols mismatch)",
    "⚠️ LKM 已加载，但 APatch: SUSFS 接口无响应（内核 SUSFS 版本可能不匹配）": "⚠️ LKM loaded but APatch: SUSFS interface not responding (kernel SUSFS version may mismatch)",

    /* ---------- 占位符 / 无障碍 ---------- */
    "页面导航": "Page navigation",
    "留空不生效": "Empty = disabled",
    "如 6.6.99-custom": "e.g. 6.6.99-custom",
    "如 #1 SMP PREEMPT": "e.g. #1 SMP PREEMPT",
    "# 每行一个挂载前缀": "# one mount prefix per line",
    "# 每行一个路径": "# one path per line",
    "# 每行一个文件路径，如 /data/adb/modules/xxx/lib.so": "# one file path per line, e.g. /data/adb/modules/xxx/lib.so",
    "APatch / KernelPatch": "APatch / KernelPatch",
    "APatch 用户态": "APatch userspace",
    "KernelPatch 内核": "KernelPatch kernel",
    "共存模式": "Coexist mode",
    "SUSFS LKM 放行": "SUSFS LKM opt-in",
    "是": "Yes",
    "否": "No",
    "已激活": "Active",
    "未知": "Unknown",
    "已放行": "Opted in",
    "未放行": "Not opted in",
    "放行 LKM": "Allow LKM",
    "取消放行": "Revoke opt-in",
    "APatch/KernelPatch 下默认不自动外挂 SUSFS LKM；需要时手动放行。放行属于实验性共存，存在崩溃风险。": "Under APatch/KernelPatch the SUSFS LKM is not auto-loaded; opt in manually if needed. This experimental coexistence can crash boot.",
    "放行后允许在 APatch/KernelPatch 内核上外挂 SUSFS LKM。这是实验性共存路径，可能与 kpimg 冲突导致启动异常；仅在明确知道风险时继续。": "This allows loading the SUSFS LKM on an APatch/KernelPatch kernel. This experimental coexistence may conflict with kpimg and break boot; continue only if you accept the risk.",
    "已取消 LKM 放行。": "LKM opt-in revoked.",
    "已放行 LKM；下次加载/应用会生效。": "LKM opt-in enabled; it takes effect on the next load/apply.",
  };

  var EXACT = {};
  var PATS = [];
  var EN_MODE = false;

  (function build() {
    for (var k in DICT) {
      if (!Object.prototype.hasOwnProperty.call(DICT, k)) continue;
      if (k.indexOf("%s") >= 0) PATS.push({ parts: k.split("%s"), en: DICT[k] });
      else EXACT[k] = DICT[k];
    }
    PATS.sort(function (a, b) { return b.parts[0].length - a.parts[0].length; });
  })();

  function isWs(ch) {
    var c = ch.charCodeAt(0);
    return c === 32 || c === 9 || c === 10 || c === 13 || c === 12 || c === 11 || c === 160;
  }

  function hasHan(s) {
    for (var i = 0; i < s.length; i++) {
      var c = s.charCodeAt(i);
      if (c >= 0x4e00 && c <= 0x9fff) return true;
      if (c >= 0x3000 && c <= 0x303f) return true;
      if (c >= 0xff00 && c <= 0xffef) return true;
    }
    return false;
  }

  function collapse(s) {
    var out = "";
    var prev = false;
    for (var i = 0; i < s.length; i++) {
      var ch = s.charAt(i);
      if (isWs(ch)) {
        if (!prev) out += " ";
        prev = true;
      } else {
        out += ch;
        prev = false;
      }
    }
    return out;
  }

  function matchPat(core) {
    for (var i = 0; i < PATS.length; i++) {
      var parts = PATS[i].parts;
      if (core.indexOf(parts[0]) !== 0) continue;
      var pos = parts[0].length;
      var args = [];
      var ok = true;
      for (var j = 1; j < parts.length; j++) {
        var seg = parts[j];
        var at;
        if (j === parts.length - 1) {
          if (seg === "") at = core.length;
          else at = core.lastIndexOf(seg);
        } else {
          at = core.indexOf(seg, pos);
        }
        if (at < pos) { ok = false; break; }
        args.push(core.slice(pos, at));
        pos = at + seg.length;
      }
      if (!ok || pos !== core.length) continue;
      return { entry: PATS[i], args: args };
    }
    return null;
  }

  function tr(core) {
    if (!core) return core;
    var hit = EXACT[core];
    if (hit !== undefined) return hit;
    var m = matchPat(core);
    if (!m) return core;
    var out = m.entry.en;
    for (var i = 0; i < m.args.length; i++) out = out.replace("%s", tr(collapse(m.args[i]).trim()));
    return out;
  }

  function trText(v) {
    if (!v || !hasHan(v)) return v;
    var a = 0;
    var b = v.length;
    while (a < b && isWs(v.charAt(a))) a++;
    while (b > a && isWs(v.charAt(b - 1))) b--;
    var lead = v.slice(0, a);
    var trail = v.slice(b);
    var core = collapse(v.slice(a, b));
    var out = tr(core);
    if (out === core) return v;
    return lead + out + trail;
  }

  function tl(v) {
    if (!v || !hasHan(v)) return v;
    var lines = String(v).split(String.fromCharCode(10));
    for (var i = 0; i < lines.length; i++) lines[i] = trText(lines[i]);
    return lines.join(String.fromCharCode(10));
  }

  function walk(node) {
    if (!node) return;
    if (node.nodeType === 3) {
      var nv = trText(node.nodeValue);
      if (nv !== node.nodeValue) node.nodeValue = nv;
      return;
    }
    if (node.nodeType !== 1) return;
    if (node.getAttribute && node.getAttribute("data-i18n-skip") !== null) return;
    var attrs = ["placeholder", "title", "aria-label"];
    for (var i = 0; i < attrs.length; i++) {
      var v = node.getAttribute(attrs[i]);
      if (!v) continue;
      var nvv = trText(v);
      if (nvv !== v) node.setAttribute(attrs[i], nvv);
    }
    var kids = node.childNodes;
    for (var k = 0; k < kids.length; k++) walk(kids[k]);
  }

  var obs = null;

  function startObserver() {
    if (obs || !document.body || typeof MutationObserver === "undefined") return;
    obs = new MutationObserver(function (list) {
      if (!EN_MODE) return;
      for (var i = 0; i < list.length; i++) {
        var m = list[i];
        if (m.type === "characterData") {
          var nv = trText(m.target.nodeValue);
          if (nv !== m.target.nodeValue) m.target.nodeValue = nv;
          continue;
        }
        for (var j = 0; j < m.addedNodes.length; j++) walk(m.addedNodes[j]);
      }
    });
    obs.observe(document.body, { childList: true, subtree: true, characterData: true });
  }

  function detect() {
    try {
      var saved = localStorage.getItem("lang");
      if (saved === "zh" || saved === "en") return saved;
    } catch (e) {}
    var nav = String(navigator.language || "zh").toLowerCase();
    return nav.indexOf("zh") === 0 ? "zh" : "en";
  }

  function apply(next) {
    var lang = next || detect();
    EN_MODE = lang === "en";
    document.documentElement.setAttribute("lang", EN_MODE ? "en" : "zh-CN");
    if (!EN_MODE) return;
    if (document.title) document.title = trText(document.title);
    if (document.body) walk(document.body);
  }

  function boot() {
    apply();
    startObserver();
  }

  if (document.body) boot();
  else document.addEventListener("DOMContentLoaded", boot);

  window.i18n = {
    apply: function (lang) { apply(lang); },
    t: function (s) { return EN_MODE ? trText(s) : s; },
    tl: function (s) { return EN_MODE ? tl(s) : s; },
    get lang() { return EN_MODE ? "en" : "zh"; }
  };
})();
