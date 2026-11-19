# 待办与已知问题

记录**已知但不在本次版本修**的问题、修法与验收标准，避免口头承诺丢失。
每条包含：现象 / 证据 / 根因 / 修法 / 验收 / 影响面。

---

## ISS-001 · `ctl.sh status` 耗时 2 秒（下一次更新修）

> Issue: [#9](https://github.com/DawnyFY/lkm-susfs-manager/issues/9)

**状态**：已定位，未修（1.2.8 不含）
**影响**：状态页首屏、`status` 相关的所有脚本调用
**优先级**：中（用户可感知，但不影响正确性）

### 现象

状态页从打开到出数据约 2 秒，「检测中」停留明显。

### 证据（设备实测，`time` 内建）

| 命令 | 实测 |
|---|---|
| `sh ctl.sh status` | **2.06 s**（real）/ 0.73 s user / **1.60 s sys** |
| `sh ctl.sh pid_guard_bundle` | 0.12 s |
| `sh ctl.sh get_bundle` | 0.18 s |
| `sh -c true`（基线） | 0.01 s |

逐项测量 `status` 内部每个 helper：`real_kernel_release` 0.02s、`_susfs_detect` 0.00s、`select_susfs_bin_fast` 0.00s、`show version` 0.01s、`show variant` 0.00s、`kernel_config_get` 0.07/0.05s、`cfg_load` 0.01s、`ksu_branch` 0.08s、`kernelpatch_*` 0.03–0.06s、`_cf_state` 0.03s、`bootloader_state` 0.02s、`install_id` 0.09s —— **合计约 0.5 s**。

### 根因

**不是某条命令慢，而是进程创建次数**：`status()` 里有 **47 处 `printf`** 输出字段，其中约 30 个字段用 `$(...)` 取子 shell（`grep`/`cut`/`stat`/`getprop`/`dumpsys` 之类），每次 fork+exec 约 30–50 ms，累计 1.2–1.5 s —— 与 `sys` 时间 1.60 s 吻合。

### 修法（方案 3：减少 fork，一次装载）

目标：**`status` 从 2 s 降到 0.5 s 以内**，输出字段与顺序保持不变。

1. **配置与模块信息一次装载，不 fork**
   - `config.ini`：用 `while IFS='=' read -r k v` 一次读入，`case "$k"` 赋给变量（替代每字段 `grep | cut`）
   - `module.prop`：同样一次读入 `version` / `description` / `versionCode`
   - `state/` 下的若干小文件（`apply_result`、`apply_fails`、`fail_count`、`boot_stage_completed`）用 shell 内建读取（`read` 或 `while read`），不再各起一个 `cat`
2. **`/proc` 类读取合并**
   - `/proc/susfs_path` 只读一次，规则数用一次 `while read` 计数（替代 `grep | grep -v | sed | awk | sort -u | wc -l` 六段管线）
   - `/proc/susfs_hide_modules` 只在需要时读一次并复用（`hide_kernelsu` 与 PID Guard 的 `hidden` 共用）
   - `/proc/modules` 读一次，`generic_pid_guard` 的 `visible` 与 `ksu` 相关判断共用
3. **按启动缓存无法变的值**
   - `ksu_branch`（0.08s）、`bootloader_state`（0.02s）、`kernelpatch_*`（0.03–0.06s）结果写 `state/.probe_cache`，键为 `/proc/sys/kernel/random/boot_id`；换启动即失效
   - 若有 `ksu_susfs` 版本缓存，键为二进制的 `size+mtime`（升级二进制自动失效）
4. **可选：合并多次 `stat`**
   - `stat -c %Y` / `stat -c %s` 两处改为一次 `stat -c '%Y %s'` 再拆分

### 现成的护栏（已落地）

- `tools/fixtures/status.baseline`：1.2.8 设备上抓取的 **49 个字段名与顺序** + volatile 列表
- `tools/test_status_keys.sh`：断言 `ctl.sh` 仍然输出基线里的每个键（离线可跑，已并入 37 个测试）
- 重构后建议：抓一份新的 `ctl.sh status` 输出，与真实运行时输出逐字段 `diff`（除 volatile）

### 验收标准

- [ ] `time sh ctl.sh status` **< 0.5 s**（设备实测，连续 3 次）
- [ ] 输出**键集合与顺序**与当前完全一致（见下方契约），逐字段与旧版比对无差异
- [ ] 现有离线套件 36+ 全绿；`webui` 的 Vitest 39+ 全绿
- [ ] 缓存失效正确：换 `boot_id` 后 `ksu_branch` / `kernelpatch_*` 重新探测（人为改 boot_id 文件验证）
- [ ] 二进制替换后版本缓存失效（改 mtime 验证）

### 输出契约（重构后必须一字不差）

```
module_version install_id description kernel kmi lkm_present susfs_kernel lkm_variant
lkm_version rules hide_kernelsu marker auto_load root_manager ksu_bin ksu_bin_path
selinux fail_count apply_fails pid_guard_enabled pid_guard_loaded pid_guard_visible
pid_guard_hidden pid_guard_result pid_guard_uids pid_guard_comms kernelpatch
apatch_userland kernelpatch_kernel kernelpatch_version coexist_mode allow_lkm
config_ksu config_ksu_susfs apply_result boot_stage_completed backend_kind
backend_interface_detected abi_match integrity lkm_size sus_mount try_umount
autoload bootloader crash_evidence effect_verified force_bl_unlocked
tool_query
```

> 注：上表是去重后的键名；**实际顺序以 `tools/fixtures/status.baseline` 为准**（已在设备抓取）。
> 重构时把新输出与该基线逐字段比对，除 `[volatile]` 段列出的字段外必须完全一致。

### 影响文件

- `module/ctl.sh`（`status()` 与 `pg_status_fields()`）
- 可能新增 `module/status_collect.sh`（把采集逻辑单独成文件，便于单测）
- `tools/test_status_keys.sh`（新增：断言键集合，防重构漏字段）

---

## ISS-008 · `set_bundle` 无法检测「4 字节边界截断」

> Issue: [#10](https://github.com/DawnyFY/lkm-susfs-manager/issues/10)

**状态**：已知未修（1.2.8 不含），定级 minor
**影响**：仅当调用方把 payload 截在 base64 的 4 字符边界上时

WebUI 保存走双层 base64：每段 `b64(内容)` → `|` 连接 → 整体 `b64`。
`ctl.sh` 已有三道防线：段数必须为 8、非空段解出 0 字节即拒绝、解出内容重编码必须与原始段一致。

但**重编码比对抓不到「合法的截断」**：把某段 base64 从尾部截到 4 的倍数长度，它仍是合法 base64，
解码得到的是内容前缀，重编码也一致 —— 实测（toybox）返回 `saved` 并写入截断内容。

为什么不在 1.2.8 修：真实链路里的超长是 `ARG_MAX` 硬失败（`Argument list too long`，exec 直接失败、
不写文件），不会截断；要彻底覆盖需要在线上格式里带长度或校验和（第 9 段或 `len:b64`），
属于改协议 + 改前端 + 改测试 + 真机复验，风险大于收益。

**下一步方案**：把线格式升级为 `len1:b64_1|len2:b64_2|…`（`len` 为解码后字节数），
`ctl.sh` 校验 `解码长度 == len`，前端 `buildBundlePayload` 同步；`tests/bundle-wire.spec.ts`
与 `tools/test_bundle.sh` 增加截断用例（toybox 与 GNU 都要跑）。

## 其它已知但未修项（沿用既有结论）

| 编号 | 问题 | 结论 |
|---|---|---|
| ISS-002 | `updateJson` 指向 `raw.githubusercontent.com`，本机两次直连超时 | 建议改成 `https://susfs.stdawns.top/update.json`（站点已在跑），需同时改 `module.prop` 并重建 |
| ISS-003 | 符号兼容闸门（`susfs-guard` 的做法） | 不照搬：零地址内核上用户态拿不到符号表；改为失败归因（见 `docs/28-gap-vs-susfs-guard.md`） |
| ISS-004 | `doctor.sh` 体检脚本 | 值得做（对报障最有用），约半天 |
| ISS-005 | 防变砖三段式（暂停 → 计数 → 自动禁用） | 值得做，需真机重启序列验证 |
| ISS-006 | 站点 `public/SHA256SUMS` 与公告的版本口径 | 必须与 GitHub Release 同批更新 |
| ISS-007 | 冷启动首次装载 | 未验证（临时 root 重启即失效，需用户配合重新注入） |

| ISS-009 | `set_bundle` 单次约 70 KB 原始内容上限（`ARG_MAX`） | 已在 `docs/CONFIG.md` 说明；超限为硬失败、不写半截文件，暂不改分段提交 |
