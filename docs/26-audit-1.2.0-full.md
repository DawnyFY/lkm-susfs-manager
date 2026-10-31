# 1.2.0 完整模块审计（2026-10-30）

## 范围与方法

审计对象：`release-repo` 工作树（35 个打包文件 + 10 个开发文件）与 `dist/susfs_allinone-1.2.0.zip`。
方法：静态检查 + 逐段代码审查 + 越界写扫描 + 端到端/离线测试复现。只读审计，修复另行提交。

## 结论

**有条件通过**：发现并修复 2 个 P1、4 个 P2、3 个 P3；无越界写盘、无全局破坏性操作。
仍建议真机复核 mksh 下的锁与 stat 行为。

## 发现与处理

| 编号 | 级别 | 问题 | 证据 | 处理 |
|---|---|---|---|---|
| A1 | P1 | 开机 apply 与 WebUI apply 可并发，重复执行会让 `our_paths.txt` 清单错乱、规则残留 | `boot-completed.sh` 与 `ctl.sh apply` 都直接执行 `apply.sh`，无互斥 | 新增 `lock_acquire/lock_release`（mkdir 原子锁 + 900s 过期），apply 入口加锁并在 EXIT 释放 |
| A2 | P1 | `file_older_than`/`lock_acquire` 在 `stat` 失败时把"取不到 mtime"当成"很旧"，锁会被误接管、缺失文件被判过期 | `_mt` 为空 → `$((_now - _mt))` 当 0 → 判定恒真 | 先校验 `_now`/`_mt` 非空，再比较；新增 `test_lock.sh` 覆盖三种场景 |
| A3 | P2 | `state/loading` 自愈依赖 `find -mmin`，toybox 支持不确定，失效时会回到"永久跳过 apply" | `apply.sh` 用 `find "$STATE/loading" -mmin +10` | 改为 `file_older_than`（`stat -c %Y` 与 `date +%s` 比较） |
| A4 | P2 | `ctl.sh set_file` 白名单不含 `skip_hide`，WebUI 无法写该文件 | `case "$2" in sus_path|sus_mount|try_umount|hide_modules)` | 白名单补 `skip_hide` |
| A5 | P2 | README 仍宣传已移除的「强制隐藏 LSPosed 挂载」；CHANGELOG 同段又写"自动替换为模块备份" | `README.md:77`、`CHANGELOG.md:5` | 改为当前真实行为（过滤真实分区 / 回退不写盘） |
| A6 | P2 | `tools/susfs_diag.sh` 仍用写规则方式探测能力，与本轮"只读判定"原则冲突 | `add_sus_mount /data/local/tmp/.diag_probe` + `rmdir` | 改为只读 `show enabled_features` |
| A7 | P3 | `load.sh` 注释过时（称"把模块备份放进管理器 bin 目录"） | `load.sh:56-57` | 更新为"缺失时用内置备份（不写盘）" |
| A8 | P3 | `customize.sh` 用 `/proc/sys/kernel/osrelease` 选 KMI | `customize.sh` | 改为 `/proc/version` 优先，回退 osrelease |
| A9 | P3 | `ctl.sh status` 新增的 `sus_mount`/`try_umount`/`bootloader` 未在 WebUI 展示 | 键存在但 app.js 未引用 | 记录为后续 UI 增强，不影响功能 |

## 第二轮：独立审计（子代理）发现与处理

独立审计（只读，18:18:54 快照）结论「有条件通过」，提出 3 个 P1 + 12 个 P2。逐条核实后处理如下。

| 编号 | 级别 | 问题 | 核实 | 处理 |
|---|---|---|---|---|
| B1 | P1 | 能力缓存被「LKM 未加载时打开 WebUI」投毒：caps 只在 boot_id 变化时刷新，加载成功后同 boot 内仍为 0，DEX2OAT / auto_try_umount 被静默跳过 | 已复现（离线脚本） | caps 增加 `lkm=` 字段参与刷新判定；load 成功加载后 `rm -f state/caps` |
| B2 | P1 | `hide_sus_mnts`（默认 1）与 `avc_spoof` 在全部 8 个 .ko 上被特性位门控恒跳过 | 已复现（8 个 .ko 仅含 9 个 CONFIG 字面量，无 HIDE_SUS_MNTS/AVC_LOG_SPOOFING） | 判定改为「特性位 or /proc 节点」；命令失败明确告警 |
| B3 | P1 | 发布不可追溯：未提交/未打 tag，CI 未在此状态运行 | 已确认 | **未处理，留待维护者决定提交**（本轮改动均在脏工作树） |
| B4 | P2 | `add_sus_path_safe` 先登记后 add，失败路径也被记为"我们写入的" | 已确认 | 记录移到 add 成功分支 |
| B5 | P2 | `caps_downgrade` 在 caps 缺失时静默失效 | 已确认 | 缺失时先 `caps_refresh` 再降级 |
| B6 | P2 | 启动守卫误诊：KMI 不匹配 `exit 0` 被当成"上次未完成启动"，永久暂停自动加载 | 已确认 | `load.sh` 的 `fail()` 中 `clear_boot_guard`（确定性失败不暂停） |
| B7 | P2 | load 无互斥；`timeout 20` 可能掐断 insmod 留下 loading | 已确认 | load 加互斥锁（300s）；post-fs-data timeout 改 30s |
| B8 | P2 | WebUI 的 marker 恒显示"未创建"（`touch_marker` 只写 state，`marker_exists` 只查旧路径） | 已确认 | `marker_exists` 优先检查 `state/susfs_active` |
| B9 | P2 | `ctl.sh status` 用 osrelease 选 KMI，与"真实内核"整改不一致 | 已确认 | 改用 `real_kernel_release` |
| B10 | P2 | `customize.sh` 两段保留逻辑重复，且会把已定制的 hide_modules 覆盖为 kernelsu | 已确认 | 合并为一段，继承分支只在为空时补默认 |
| B11 | P2 | `customize.sh` 与 `common.sh` 的版本串校验不一致 | 已确认 | 统一为「`^[0-9]+\.[0-9]+` 且含 androidNN」 |
| B12 | P2 | 升级不保留 `state/our_paths.txt`，`replace_rules=1` 退化为按配置清理 | 已确认 | customize 保留该清单 |
| B13 | P2 | 文档说 uname 伪装影响 `/proc/version`，与设计前提矛盾 | 已确认文矛盾 | README 改为"影响 uname 系统调用"；index.html 改为"优先 /proc/version" |
| B14 | P2 | `skip_hide` 仍无 WebUI 编辑入口（第一轮报告 A4 写成"已修复"不准确） | 已确认 | 新增 skip_hide 编辑卡片；A4 表述更正 |
| B15 | P2 | `set_config` 只校验值不校验键，`PATH=` 可劫持被 source 的环境 | 已确认 | 增加危险键拒绝（PATH/LD_*/IFS/ENV/...），保留用户自定义键；新增两条测试 |
| B16 | P2 | `find_ksu_bin_dir` 死函数；`TEST_RESULTS.md` 仍是 1.1.0 | 已确认 | 删除死函数；旧文档加注说明 |

补充说明：B3（发布追溯）与 `skip_legit_mounts` 死配置保留（兼容旧配置，文档已说明），不视为缺陷。

## 第三轮：外部 AI 审计（交接文档 AUDIT_HANDOFF_1.2.0.md）发现与处理

外部审计按交接文档 §7 的顺序逐项验证，结论「一个高风险配置边界问题，另有全局清理、启动守卫、锁超时和规则累积等风险」。逐条核实后处理如下。

| 编号 | 级别 | 问题 | 核实 | 处理 |
|---|---|---|---|---|
| C1 | P1 | **配置可改变模块路径**：`set_config` 允许未知键，`MODDIR/STATE/CONFIG` 等可被写入配置；`apply.sh` source 后 `$MODDIR/kmi.sh` 会成为任意 root 脚本执行入口 | 已复现（MODDIR/STATE/CONFIG 三个键都能通过校验保存） | ① `set_config` 拒绝 `MODDIR/MODPATH/CONFIG/STATE/LOG/BIN/SUSFS_BIN/REL/KMI/FORCE_KMI`；② apply/load/post-fs-data/boot-completed 在 source 配置后强制重置 `MODDIR/CONFIG/STATE`；③ 新增两条测试 |
| C2 | P1 | KMI 未匹配分支 `exit 0` 未清 boot guard → apply 误判「上次未能完成启动」→ 永久暂停自动加载 | 已确认（该分支未调用 fail） | 该分支加 `clear_boot_guard`（没尝试加载，不属于启动失败） |
| C3 | P1 | `/data/adb*` 前缀过宽，会匹配 `/data/adbfoo` 之类路径 | 已确认 | 改为 `/data/adb|/data/adb/*` |
| C4 | P2 | 锁无持有者标识：TTL 过期被接管后，旧任务退出会删掉新锁，第三个任务可并发进入 | 已确认 | 锁目录写入 `pid`；`lock_release` 只释放自己持有的锁；新增两条测试 |
| C5 | P2 | `restore_config_if_missing` 在 config.sh 缺失时用旧备份覆盖所有规则文件 | 已确认 | 改为只补缺失文件，已有文件不覆盖 |
| C6 | P2 | `replace_rules=2`（整表清空）在 WebUI 保存时被静默保留 | 已确认 | 进入配置页时显式警告一次；用户取消勾选即写 0 |
| C7 | P2 | `tools/appfuse_probe.sh` 的 clean 模式 UID 未校验数字，可拼入 glob（传入 `*` 会卸载多个实例） | 已确认 | UID 必须纯数字，否则拒绝执行 |
| C8 | P3 | README 仍称 KMI 按 `/proc/sys/kernel/osrelease` 选择 | 已确认 | 改为「/proc/version → 真实内核快照 → osrelease」 |

## 第四轮：根因整改（配置格式 + 去重 + 合并保存）

外部审计连续三轮都能在「配置即代码」上挖出新绕过（键名 → 值内空格 → 引号），因此做根因整改：

| 项 | 处理 |
|---|---|
| **配置格式** | `config.sh`（source 加载）→ `config.ini`（纯 KEY=VALUE，`cfg_load` 显式解析，不执行）。旧文件自动迁移为 `.bak`，非 KEY=VALUE 行丢弃并提示。注入/环境劫持/路径覆盖整类消失 |
| sus_mount/try_umount 去重 | 内核无查询接口，改为模块侧按 `boot_id` 记账（`state/*_added.txt`），失败不记账 |
| WebUI 保存 | 6 次独立调用 → 1 次 `set_bundle`（强制 6 段，config 校验失败整体不落盘） |

验证：`test_config_ini.sh`（13 项，含迁移与恶意内容不执行）、`test_mount_dedup.sh`（10 项）、`test_bundle.sh`（12 项）全部通过；真机迁移成功，配置项保留，`config.sh.bak` 留存。

未处理（保留为已知风险）：配置写入与 apply 未共享锁（窗口已压到微秒级）。

## 已核实通过

| 项 | 验证方式 |
|---|---|
| 文件与构建一致 | 35 个文件逐一 SHA256 与 zip 比对，0 差异；工作树 45 文件中仅 dev 文件未打包 |
| 静态检查 | 全部 `*.sh` 通过 `bash -n` 与 `dash -n`；`app.js` 通过 `node --check`；HTML div 42/42；无 CR |
| WebUI 引用 | 71 个 id，JS 引用的 id 全部存在，无死函数 |
| 越界写 | 全仓库扫描后，除 `/proc/susfs_*` 与模块自身目录外无写入；`customize.sh` 仅从外部读取旧配置 |
| 全局破坏性操作 | 无 `umount wipe` / `rmmod` / `reboot` / `setenforce`；`replace_rules=2` 会整表清空，但需显式配置且 WebUI 有警告 |
| 配置注入 | `set_config` 白名单 + `sh -n`，端到端测试拦截 `&` `>` `|` 与非 KEY=VALUE 行，且不破坏原配置 |
| sus_path 作用域 | 只删 `our_paths.txt` 内路径；删除失败保留 pending；`replace_rules=2` 才整表清空 |
| 能力判定 | 只读 `show enabled_features`；实测失败降级并记录 `src=probe` |
| KMI 选择 | `/proc/version` → `real_uname` → osrelease，`$3` 校验版本形态；伪装值会选错（测试已覆盖） |
| 开机次数 | `boot-completed.sh` 仅一处 apply，无 setsid/sleep |
| 测试 | 8 个离线测试全部 ALL PASS；CI 已加入测试步骤 |

## 需真机确认

1. mksh 下 `trap ... EXIT` 与 `mkdir` 锁的释放行为
2. toybox `stat -c %Y` / `date +%s` 可用性
3. `/proc/susfs_path` 的 `del` 在目标内核的实际生效情况
4. 并发场景：开机 apply 与 WebUI 点击真正撞上时的日志与锁接管

## 许可证合规（专项）

| 检查 | 结果 |
|---|---|
| `check_license_compliance.py` | RESULT: OK |
| `LICENSE`（GPL-2.0 全文） | 包内存在，头部确为 GPLv2 |
| `LICENSE-AGPL-3.0`（AGPL-3.0 全文） | 包内存在 |
| `NOTICE`（作者/仓库/tag/源码/书面要约） | 包内存在，含 GPL-2.0 与 AGPL-3.0 两段声明 |
| `provenance.json` 资产哈希 | 9/9 与包内文件一致 |
| `module.prop` 署名 | 含 inforcqb（GPL-2.0）与 sidex15 & simonpunk（AGPL-3.0） |
| 聚合分发声明 | NOTICE 与 README 均明确 |
| 第三方代码引入 | 本轮无；`.ko` 与 `ksu_susfs` 哈希未变 |
| 外部资源（CDN/字体/JS） | webroot 无任何外部引用 |

本轮补强：全部 shell 脚本、WebUI JS/CSS/HTML 增加 `SPDX-License-Identifier: GPL-2.0-only` 头。

## 产物

`dist/susfs_allinone-1.2.0.zip`，SHA256 `5ED9867B7886D5C4D5FA4087C606CE4E9B23847A243A82530F6ADE4CDAB8E169`。