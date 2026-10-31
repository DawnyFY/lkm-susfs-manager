# LKM SUSFS管理器（susfs_allinone）— 代码审计交接文档

> 给接手审计的 AI：本文档提供项目背景、结构、已做过的改动、已知风险点与复现方式。
> 请在只读前提下审计；不要直接改文件、不要执行 adb 操作、不要 git 提交。
> 一切以代码与实际运行结果为准，不要直接采信本文档或项目文档里的措辞。

## 0. 审计对象

| 项 | 值 |
|---|---|
| 项目 | LKM SUSFS管理器（模块 id: susfs_allinone） |
| 版本 | 1.2.0（versionCode 12） |
| 代码位置 | D:\aimod\ksu-audit\release-repo |
| 构建产物 | dist/susfs_allinone-1.2.0.zip（37 个文件） |
| 许可证 | 本项目 GPL-2.0；LKM GPL-2.0（inforcqb）；ksu_susfs AGPL-3.0（sidex15 & simonpunk），聚合分发 |
| 状态 | 工作树未提交（HEAD 为 1.1.6 时期），dist/ 被 gitignore |
| 产物哈希 | 6FB4F49654E8A82722A6002E05553650E4553081649A2D1579DFAA5A8E1098D1 |

## 1. 项目做什么

KernelSU 系列管理器（KernelSU / SukiSU / ReSukiSU / KernelSU Next）的模块，负责：

1. 按当前内核自动匹配 KMI（8 种：android12-5.10 ~ android17-6.18），加载模块自带的 SUSFS LKM（susfs_guard_lkm-<kmi>.ko）
2. 下发隐藏规则：sus_path（路径隐藏）、hide_modules、sus_mount、try_umount、uname 伪装、cmdline 伪装、Scene 痕迹、GAPPS/DEX2OAT、vendor sepolicy、VOLD 隔离
3. 提供中文 WebUI（KernelSU 管理器内打开）：状态 / 配置 / 日志 / 关于

目标设备场景：未解锁 bootloader 的临时 root（fastboot 注入 ABL cmdline → SELinux permissive → ksud late-load），也支持已解锁 BL 的常驻 root。

## 2. 运行环境与限制

| 项 | 说明 |
|---|---|
| 架构 | arm64 only（安装脚本会 abort 其他架构） |
| root | KernelSU 系列，late-load 或常驻 |
| 内核 | GKI，需支持外部模块加载（init_module 不被 modules_disabled / 签名 / lockdown 拦） |
| Shell | 设备为 Android mksh/toybox；脚本须兼容 busybox/mksh，不能依赖 bash 特性 |
| 网络 | 不需要：WebUI 无 CDN、无外部字体、纯本地资源 |

## 3. 目录结构与文件职责

打包进 zip 的 37 个文件（含贡献者头像与 config.ini.default）：

    module.prop              模块元信息（version/versionCode/author 含上游署名）
    kmis                     支持的 KMI 列表（一行一个）
    kmi.sh                   KMI 选择：select_kmi/list_kmis/guess_kmis
    skip_mount               空文件，KernelSU 约定（禁止 overlay 挂载本模块）
    LICENSE                  GPL-2.0 全文
    LICENSE-AGPL-3.0         AGPL-3.0 全文
    NOTICE                   第三方组件声明 + 源码地址 + 3 年书面要约
    provenance.json          9 个第三方二进制的来源与 sha256

    common.sh (675 行)       公共库：root 识别、二进制选择、KMI、锁、路径作用域、
                             能力探测、配置自愈、boot guard、BL 状态、诊断
    apply.sh (524 行)        规则下发主流程，按 1~9 分节（见 §4.2）
    load.sh (201 行)         LKM 加载：KMI 匹配 → insmod → 校验 → 描述更新
    ctl.sh (380 行)          WebUI 后端：白名单命令 + 输入校验
    action.sh (33 行)        管理器 Action：手动 load + apply + 摘要
    customize.sh (92 行)     安装：架构检查、KMI 选择、保留旧配置/规则清单、权限
    post-fs-data.sh (24 行)  开机早期：boot guard + 只加载 LKM
    boot-completed.sh (20 行) 开机完成：只执行一次 apply
    config/config.ini        用户配置（纯 KEY=VALUE，不 source）
    config/config.ini.default 默认值模板（缺失时恢复用）
    config/sus_path.txt      隐藏路径清单
    config/sus_mount.txt     挂载隐藏清单
    config/try_umount.txt    卸载清单
    config/hide_modules.txt  要隐藏的模块名（默认 kernelsu）
    config/skip_hide.txt     不隐藏的包名/路径片段（子串匹配，可注释）
    bin/susfs_insmod         LKM 加载器（解析符号、绝对化、vermagic 修补）
    bin/ksu_susfs_good       ksu_susfs 回退副本（AGPL-3.0）
    lib/susfs_guard_lkm-*.ko 8 个 KMI 的 LKM（GPL-2.0，未修改）
    webroot/index.html       WebUI 结构（4 个 tab）
    webroot/app.js (718 行)  WebUI 逻辑：ksu.exec 封装、状态轮询、配置读写
    webroot/style.css        MIUIX 风格样式
    webroot/contributor-*.jpg 贡献者头像

开发文件（不打包）：tools/（构建与校验脚本、诊断脚本、13 个测试）、docs/（审计报告）、dist/、state/。

## 4. 核心机制

### 4.1 加载流程（load.sh）

1. 日志轮转（>64KB 只留 200 行）→ 重定向到 load.log
2. save_real_uname：开机时第一件事，把真实内核写 state/real_uname.txt
3. 早退：disable / remove / disable_autoload（非 manual）/ 安全模式
4. 互斥锁 state/load.lock（300s 过期）
5. ensure_susfs_bin：优先管理器自带 ksu_susfs，缺失时用模块备份（不写盘）
6. autoload_paused 检查（boot guard）
7. lkm_present（/proc/susfs_path 或 /sys/module）→ 已加载则跳过
8. REL=$(real_kernel_release)：/proc/version → state/real_uname.txt → osrelease
9. select_kmi → 匹配不到时写 install_kmi.txt/描述并 exit 0（不加载）
10. susfs_insmod 加载，失败时：EPERM 打印诊断清单；其余 fail
11. 校验 ksu_susfs show variant/version，成功则 rm state/caps 并写描述

### 4.2 应用流程（apply.sh 分节）

| 节 | 内容 |
|---|---|
| 1 | 确保 LKM（未加载则调用 load.sh） |
| 2 | 选择 ksu_susfs（不可用回退备份） |
| 3 | 等待 /sdcard/Android/data（最多 15s），设 sdcard/android_data 根路径 |
| 4 | hide_sus_mnts（特性位 or /proc 节点）、avc_spoof（失败则本 boot 标记不可用） |
| 5 | sus_path：replace_rules=1 只删 our_paths.txt 内；=2 整表 clear |
| 5b | 扩展开关：compat_matrix / revanced / custom_rom / gapps / dex2oat / scene |
| 5c | 仅解锁 BL：vendor sepolicy、VOLD 隔离（bl_unlocked 门控；支持 `force_bl_unlocked=1` 手动覆盖） |
| 5d | GAPPS / DEX2OAT（挂载级隐藏） |
| 5e | Scene 痕迹（/dev 下随机目录，3 轮扫描） |
| 5f | 自动 try_umount（默认关；无条件过滤真实分区；成功写 state/try_umount_auto.txt） |
| 6 | sus_mount 清单 |
| 7 | try_umount 清单 |
| 8 | hide_modules |
| 8b | uname 伪装（spoof_uname） |
| 9 | backup_config + state marker + 规则统计 |

### 4.3 能力探测

susfs_feature_enabled CONFIG_... 只读 ksu_susfs show enabled_features。
结果缓存在 state/caps（含 lkm= 与 boot_id=）；LKM 装载状态或 boot_id 变化会重算。
真正调用失败时 caps_downgrade 写 0 并标记 src=probe。

### 4.4 sus_path 作用域

state/our_paths.txt 记录本模块写过的路径：

- replace_rules=1：逐条 del 清单内路径；删除失败写入 our_paths.pending.txt 并保留到下次
- 首次升级无清单：按 config/sus_path.txt 逐条删（clear_migrated_paths）
- replace_rules=2：echo clear（整表清空，高危）

### 4.5 WebUI

- ksu.exec 调用 ctl.sh <cmd>，输出按 key=value 解析
- 保存配置：读原文 → mergeConfigText 更新已知键、保留未知键/注释 → base64 → set_config
- replace_rules=2 在 UI 是开关+原值保留；skip_detection_paths 有独立开关
- 规则文件用 textarea 编辑（sus_path / hide_modules / skip_hide / sus_mount / try_umount）
- 读取失败会禁用保存，避免空内容覆盖

### 4.6 配置格式与校验（config.ini）

配置是**纯数据文件** config.ini，由 cfg_load 逐行解析成变量，**不再被 source**：
- 值永远不会被 shell 执行，命令注入/环境劫持这类问题从根上消失
- 允许的键是白名单（cfg_load 里显式 case），未知键保留但不生效
- ctl.sh set_config / set_bundle 仍做值字符校验（防止奇怪内容进文件）
- 旧 config.sh 首次运行会自动迁移：只提取 KEY=VALUE 行（绝不 source），原文件保留为 config.sh.bak

## 5. 1.2.0 已做的整改（审计时需要核对是否真的落地）

| 项 | 内容 |
|---|---|
| KMI | 用真实内核（/proc/version 优先），避免 uname 伪装导致选错 .ko |
| 开机次数 | 只执行一次 apply（去掉了 1.2.0 中途加过的 45 秒补跑） |
| sus_path 清理 | 只删自己清单内路径；整表清空需显式 replace_rules=2 |
| 能力判定 | 从写规则探测改为只读特性位 + 实测失败降级 |
| 自动 try_umount | 默认关；开启后强制过滤真实分区；记录清单 |
| 隐藏 LSPosed | 已整块移除（它会登记全局挂载表，越界影响其他模块） |
| 管理器二进制 | 不再覆盖 /data/adb/ksu/bin/ksu_susfs，只在本次运行回退备份 |
| skip_hide | 从硬编码改为配置文件，缺失自动生成，WebUI 可编辑 |
| 并发 | apply 与 load 都加了 mkdir 互斥锁，EXIT 释放 |
| 配置 | 安装保留 config + state/our_paths.txt；配置自愈；键值双重校验 |

### 5.1 最近一轮外部审计发现并已修复（请勿重复报告）

| 问题 | 修复 |
|---|---|
| 配置可改 MODDIR/STATE/CONFIG → 可让 root source 任意脚本 | set_config 拒绝保留键（MODDIR/MODPATH/CONFIG/STATE/LOG/BIN/SUSFS_BIN 等）；四个入口 source 配置后强制重置路径 |
| KMI 未匹配分支不清 boot guard → 永久暂停自动加载 | 该分支加 clear_boot_guard（没有尝试加载，不算启动失败） |
| /data/adb* 前缀过宽（会匹配 /data/adbfoo） | 改为 /data/adb 或 /data/adb/* |
| 锁无持有者标识，TTL 被接管后旧任务会删新锁 | 锁目录记录 pid，lock_release 只释放自己持有的 |
| restore_config_if_missing 用旧备份覆盖较新规则文件 | 只补缺失文件，已有内容不覆盖 |
| replace_rules=2 在 WebUI 保存时被静默保留 | 进入配置页显式警告一次 |
| tools/appfuse_probe.sh clean 模式 UID 未校验 | 强制纯数字，否则拒绝执行 |
| README 称 KMI 按 /proc/sys/kernel/osrelease 选择 | 改为 /proc/version → 真实内核快照 → osrelease |
| **配置值可含空格**：`k=v touch /tmp/x` 通过旧校验，source 时被拆成"赋值+命令"；`auto_load=1 STATE=x export STATE` 同理 | 值改为紧凑 token 校验：空白/引号/反斜杠/元字符全部拒绝；测试覆盖这两个真实载荷 |
| post-fs-data / boot-completed 只重置了 MODDIR，STATE/CONFIG 仍可被配置覆盖 | 两个脚本补 CONFIG/STATE 重置 |
| 锁过期接管非原子：两个进程同时判定过期会互删新锁 | 改用 mv 原子抢占，只有一方能重建锁；新增并发接管测试 |
| 包内文件数与文档不一致（35/36/37 多次漂移） | 文档已更正为 37 |
| 伪回锁设备被判成 locked，vendor sepolicy / VOLD 隔离不可用（issue #7） | 状态页新增「手动确认 BL 已解锁」开关：写入独立标记 `state/force_bl_unlocked`，首次开启要求等待 10 秒确认；`bl_unlocked` 优先读该文件；新增 test_bl_override.sh |
| 倒计时只在前端：`set_config`/`set_bundle` 可直接写 `force_bl_unlocked=1` 绕过确认 | 该值改存 `state/force_bl_unlocked`（通用配置写入器只碰 config.ini）；校验器把该键列为保留键并拒绝重复键；旧值一次性迁移后删除 |
| `ctl.sh` 信任调用方环境变量 `MODDIR/CONFIG/STATE`，可把配置写到模块外 | `ctl.sh` 固定模块路径，`common.sh` 的 CONFIG/STATE 只从 MODDIR 推导（不再接受环境覆盖） |
| sus_mount/try_umount 重复 apply 会让内核列表累积（内核无查询接口） | 模块侧按 boot_id 记账去重（state/*_added.txt），失败不记账、下次重试；新增 test_mount_dedup.sh |
| WebUI 保存是 6 次独立调用，apply 可能读到「新配置 + 旧规则文件」 | 合并为 set_bundle 单次调用（config + 5 个规则文件一起提交，config 校验不通过则整体不落盘）；新增 test_bundle.sh |
| **配置靠 source 加载**：配置内容可执行任意命令、改 MODDIR/STATE/PATH（三轮审计各挖出一种绕过） | **配置改为 config.ini 纯数据格式，不再 source**；旧文件自动迁移并保留 .bak；新增 test_config_ini.sh（13 项，含迁移与恶意内容不执行） |

## 6. 已知问题与遗留（请重点看）

1. BL 状态判定不可信：bootloader_state 只看 ro.boot.verifiedbootstate/flash.locked/secureboot.lockstate，伪回锁（属性被伪装）设备会被判成 locked，导致 vendor sepolicy / VOLD 隔离被跳过。issue #7 已提，未修。
2. 特性位与真实能力不一致：8 个 .ko 里没有 HIDE_SUS_MNTS/AVC_LOG_SPOOFING/TRY_UMOUNT 字面量，但 /proc/susfs_hide_mounts、/proc/susfs_avc_spoof 节点存在。当前用特性位 or /proc 节点判定；avc 实测仍失败（已做本 boot 标记）。
3. ~~sus_mount/try_umount 无去重~~ 已改为模块侧按 boot_id 记账去重（state/*_added.txt），内核侧是否幂等不再影响模块行为。
4. skip_legit_mounts 已是死配置（过滤不可关闭），但 config/WebUI 仍写它。
5. 升级不保留 state/ 其他文件：只保留 our_paths.txt，cap/日志会重置。
6. 发布流程：工作树未提交、未打 tag，dist/ 被 gitignore；无法从 commit 复现 zip。
7. /proc/version 是否会被 set_uname 改写：本模块按可信设计，但未真机定案（文档已改为不承诺）。
8. toybox 兼容：锁/自愈依赖 stat -c %Y、date +%s；mksh 下 trap ... EXIT 未真机验证。
9. 配置写入（WebUI）与 apply 仍未共享锁：set_bundle 把跨文件窗口压到微秒级，但 apply 落在写入与 apply 之间时仍可能读到旧规则文件（影响仅为一次下发布错，下次 apply 修正）。
10. 迁移边界：旧 config.sh 里如果有非 KEY=VALUE 行（用户手写的 if/export 等），迁移时会丢弃并计数提示；目前没有发现真实用户这样写过。

## 7. 审计重点建议（按可疑度）

1. 越界写：确认除 /proc/susfs_* 与模块自身目录外没有写入（历史包袱：曾覆盖管理器二进制、写过 /data/adb/ksu/susfs4ksu/logs、删除过 /data/local/tmp 目录）
2. 全局影响：任何清空/整表操作是否只作用于自己（sus_path / hide_modules / try_umount）
3. 配置注入：config.sh 会被 root source，校验是否可绕过（键/值/多行/编码）
4. 状态机：load → apply → boot guard 的失败路径是否会卡死到下次开机
5. 并发：boot-completed 与 WebUI 同时触发时的锁行为
6. 卸载/升级：customize.sh 的保留逻辑、restore_config_if_missing 是否可能用旧值覆盖新值
7. 文档一致性：README/RELEASE_NOTES/CHANGELOG 与代码是否一致（本项目历史上多次出现文档超前）

## 7.1 审计流程（建议按顺序执行）

0. **环境**：解压交接包，代码在 `source/`（66 个文本文件，不含二进制）。只读审计；不要执行 adb、不要改文件、不要 git 操作。
1. **一致性**：核对模块包 SHA256 与 §0 一致；把模块 zip 内与 `source/` 重合的文件逐个比对哈希。
2. **静态**：`bash -n` / `dash -n` 全部脚本；`node --check webroot/app.js`；HTML 标签配平；CRLF；JS 引用的 id 是否存在；有无死函数。
3. **测试**：跑 `tools/test_*.sh`（13 个），应全部 `ALL PASS`；抽查断言是否真的覆盖行为（而不是永真）。
4. **构建校验**：`build_module_zip.py` → `check_zip.py` → `check_license_compliance.py`，应全部 OK；确认 zip 不含 docs/tools/state/日志。
5. **逐项审计**：按 §7 的七个重点（越界写、全局影响、配置注入、状态机、并发、升级/卸载、文档一致性）。
6. **对抗测试**：自己构造恶意输入打配置、路径、锁、bundle，验证「拒绝或无害」，不要只看代码注释。
7. **输出**：结论（通过 / 有条件通过 / 不通过）+ 按 P0/P1/P2 分级的问题清单（文件:行号、证据、影响、建议）+ 已核实通过项 + 需真机确认项。

### 已有修复的核对方式

§5.1 列出的问题文档声称已修，请用代码/测试验证而不是采信文字。例如：

- 配置注入：试 `MODDIR=... / k=v touch /tmp/x / 引号 / 重定向`，应全部被 `set_config` 拒绝；`cfg_load` 不执行任何值
- 越界写：grep 所有 `cp/mv/>` 目标，确认只有模块目录与 `/proc/susfs_*`
- 锁：模拟过期锁并发接管，应只有一个成功；旧持有者退出不得删除新锁
- 挂载去重：`sus_mount_add_once` 同路径第二次应返回 2，且不调用内核

## 8. 复现与验证命令

    # 静态检查
    for f in *.sh tools/*.sh; do bash -n "$f"; dash -n "$f"; done
    node --check webroot/app.js
    python tools/check_no_crlf.py

    # 离线测试（13 个，全部应 ALL PASS）
    for t in tools/test_*.sh; do sh "$t" "$PWD"; done

    # 构建与校验
    python tools/build_module_zip.py
    python tools/check_zip.py
    python tools/check_license_compliance.py dist/susfs_allinone-1.2.0.zip

    # 产物与工作树一致性（逐文件 sha256）
    python - <<PY
    import zipfile,hashlib,os
    z=zipfile.ZipFile("dist/susfs_allinone-1.2.0.zip")
    bad=[(n,"missing") for n in z.namelist() if not n.endswith("/") and not os.path.exists(n)]
    bad+=[(n,"diff") for n in z.namelist() if not n.endswith("/") and os.path.exists(n)
          and hashlib.sha256(z.read(n)).hexdigest()!=hashlib.sha256(open(n,"rb").read()).hexdigest()]
    print(bad or "consistent")
    PY

## 9. 许可证合规（必须保持）

- 本项目代码 GPL-2.0（LICENSE），脚本与 WebUI 已加 SPDX-License-Identifier: GPL-2.0-only
- lib/*.ko、bin/susfs_insmod：inforcqb/susfs4ksu-lkm v2.3.0-r18.4，GPL-2.0，未修改（provenance 哈希需一致）
- bin/ksu_susfs_good：sidex15 & simonpunk/ksu_module_susfs v1.5.2-R28，AGPL-3.0，未修改
- NOTICE 必须包含作者/仓库/tag/源码地址/3 年书面要约
- module.prop 的 author 必须保留上游署名
- 审计时请确认 provenance.json 的 9 个 sha256 与包内文件一致，且没有新增未声明第三方代码

## 10. 关键代码索引

| 位置 | 作用 |
|---|---|
| common.sh:44 ensure_susfs_bin | 二进制选择（不写盘） |
| common.sh:65 select_susfs_bin | 回退备份 |
| common.sh:150 apply_hide_modules | 写 /proc/susfs_hide_modules |
| common.sh:220 save_real_uname | 记录真实内核 |
| common.sh:267/275 mark/clear_boot_guard | 启动守卫 |
| common.sh:302/320 bootloader_state/bl_unlocked | BL 状态（见遗留 1） |
| common.sh:334 is_legit_partition_mount | 真实分区过滤 |
| common.sh:345~365 lock_acquire/lock_release/file_older_than | 互斥与时间判断 |
| common.sh:377 real_kernel_release | 真实内核三级回退 |
| common.sh:404~472 | sus_path 作用域管理 |
| common.sh:521~559 | 能力探测与降级 |
| common.sh:614/628 ensure_skip_hide_file/is_detection_app_path | 跳过隐藏列表 |
| apply.sh:82~517 | 规则下发全流程 |
| load.sh:89~201 | LKM 加载与失败诊断 |
| ctl.sh:236~300 | set_config/set_file/set_auto 校验 |
| webroot/app.js:61~79 mergeConfigText | 配置读-改-写 |

## 11. 需要真机才能验证（离线无法定案）

1. mksh 下 trap ... EXIT 释放锁、mkdir 锁原子性、stat -c %Y/date +%s
2. /proc/susfs_path 的 del 返回码语义（决定删除失败保留 pending 是否有效）
3. 本 LKM 是否接受 hide_sus_mnts_for_non_su_procs / enable_avc_log_spoofing / set_uname 超调用
4. 内核侧 add_sus_mount/add_try_umount 是否去重
5. boot-completed 阶段 /sdcard 是否已挂载
6. 8 个 KMI 的真实加载成功率（尤其 android16-6.12 / android17-6.18）
7. ksu.exec 90 秒超时、返回值编码在真实 WebView 中的行为
8. /proc/version 是否被 uname 伪装改写

## 12. 已知设备环境（供参考）

| 设备 | 内核 | root | 结果 |
|---|---|---|---|
| 维护者测试机 | 6.6.77-android15-8 | SukiSU Ultra 临时 root | 加载正常，规则生效 |
| 用户反馈机 A | 6.12.35/6.12.58-android16 | GhostLock 注入 + late-load | 曾出现检测异常（交互未定案） |
| 用户反馈机 B | 6.1.141-android14-11 | KernelSU Next | init_module EPERM，LKM 无法加载（内核侧拒绝） |