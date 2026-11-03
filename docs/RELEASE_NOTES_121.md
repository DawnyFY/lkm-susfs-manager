# LKM SUSFS管理器 1.2.1

本次只做一件事：**升级内核模块（LKM）到上游 `v2.3.0-r18.6`**。

## 为什么升

`v2.3.0-r18.6` 修了一个会**开机变砖**的问题：

> #159 — 在 5.15 以下内核上，`filename_lookup()` 之后不应再调用 `putname()`；原来的写法会造成 create_gate double free（双重释放）并触发 bootloop。同一处潜伏路径在 `susfs_or_entry.c` 也已修正。

也就是说：如果你用的是 Android 12/13（5.10 / 5.15 内核），旧版 LKM 在某些挂载/创建场景下可能直接把系统搞崩。1.2.1 换掉了这个实现。

## 顺带的变化

| 项 | 变化 |
|---|---|
| 挂载前缀表容量 | 8 → **64**（`#125/#133`），容器或多挂载场景不再被截断 |
| `/proc/susfs_map` | 新增（`#145`），可用 `add` / `del` / `clear` 管理 mmap 隐藏规则 |
| `readlink` 行为 | 被隐藏的文件现在对 `readlink` 返回 `ENOENT`（`#142`），与 `stat` / `open` 保持一致 |
| `susfs_insmod` | 同步更新，修了 vermagic 不匹配时的 SIGSEGV（`#150`），现在能正常修补并重试加载 |
| 隔离进程 / 隐藏符号 | `#134`、`#126` 修正 |

## 挂载隐藏换了接口

上游把 `add_sus_mount` / `add_try_umount` 标成了 deprecated，改用 `/proc/susfs_hide_mounts` 前缀表。

- `config/sus_mount.txt` 现在每行写一个**挂载前缀**，直接进 `/proc/susfs_hide_mounts`（上限 64 条）
- 旧内核（`add_sus_mount` 仍可用时）自动回退到逐条注册，行为不变
- `replace_rules=1` 会撤销本模块加过的前缀，不动上游默认的 `/data/adb/`
- 配置注释与 WebUI 说明已改成「前缀」语义
- **DEX2OAT 隐藏也一并迁移**：原来同样走 `add_sus_mount`，在这类内核上一直没生效；现在优先写前缀表，旧内核才回退

## 新接入：sus_map（mmap 隐藏）

r18.5 的 `#145` 给 `SUS_MAP` 特性补上了用户态接口 `/proc/susfs_map`——之前这个特性位一直是空转。

现在 `config/sus_map.txt` 每行写一个文件路径，apply 时会 `add` 进 `/proc/susfs_map`，隐藏进程 `maps` / `smaps` / `map_files` / `pagemap` 里的真实文件路径。典型用途是藏 LSPosed / Zygisk 注入的 so。

- 规则容量以内核实际为准（本机 `rules: N/64`），超过会提示
- `replace_rules=1` 会撤销本模块加过的
- 路径不存在时跳过并写日志

## 不变的部分

- 8 个 KMI 的 `.ko` 全部替换，文件名与匹配逻辑不变
- 启用特性仍是那 9 个（`SUS_KSTAT` / `SUS_PATH` / `ENABLE_LOG` / `SPOOF_CMDLINE` / `SUS_MAP` / `HIDE_KSU_SUSFS_SYMBOLS` / `SPOOF_UNAME` / `SUS_MOUNT` / `OPEN_REDIRECT`）
- `add_sus_mount` / `add_try_umount` 仍是 deprecated（见 #5），模块的能力探测与跳过不变

## 验证情况

静态验证已完成：

- 8 个 `.ko` 的 ELF 架构均为 AArch64（e_machine=183）
- 特性位与 r18.4 一致（9 个），没有新增需要适配的接口
- `vermagic` 与 r18.4 相同（同为 `6.6.127-4k-...-dirty`），由 `susfs_insmod` 在加载时修补
- `provenance.json` / `NOTICE` / `README` 的版本与哈希全部更新为 r18.6

**真机验证要等下一次 root 重建**：新 `.ko` 只有在重新 late-load 或重启后才会被加载，当前运行中的还是 r18.4。
加载后请确认：

```sh
su -c "sh /data/adb/modules/susfs_allinone/ctl.sh status"
su -c "cat /proc/susfs_hide_mounts"
```

预期：状态正常、`/proc/susfs_hide_mounts` 报告前缀表容量为 64。

## 已知限制

- `TRY_UMOUNT` 未实现，对应功能明确跳过并写日志；`hide_sus_mnts` 与 `avc_spoof` 走「特性位或 /proc 节点存在即执行」判定，节点在就会尝试
- 只支持官方 GKI 内核，厂商自改内核不保证可用

## 下载

https://github.com/DawnyFY/lkm-susfs-manager/releases/tag/v1.2.1

升级直接覆盖安装。**如果你用的是 5.10 / 5.15 内核，建议升级**——那是 #159 影响的范围。