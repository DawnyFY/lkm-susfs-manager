# FORK：上游 LKM 的 fork 计划（1.3.3 起）

> 状态：**Phase 0 已完成**（源码已 vendor，见 `source/upstream-lkm/VENDORED.md`），
> 尚未打任何补丁，产物仍用上游原版 `.ko`。

## 为什么 fork

三件事逼出来的：

1. **上游不导出符号**：`ver2.3.0` 的 `__ksymtab` 为空，别的模块无法复用它的 loop / uname / try_umount 实现
2. **管理器自带 `ksu_susfs` ABI 不符时能力腰斩**：这三条命令只有 supercall 通道
3. **`avc_spoof` 改 scontext 会被检测器判「审计被改写」** —— 只有改内核侧「不产生记录」才能根治

## 许可与合规

- 上游 GPL-2.0，fork 仍是 GPL-2.0；`source/upstream-lkm/LICENSE` 原样保留
- 发布二进制时源码在仓库同版本可查；`provenance.json` 需记录「fork 自 ver2.3.0 + 补丁列表」
- 补丁文件本身也随仓库分发，便于他人复现构建

## 补丁规划（每条一个 commit，便于 rebase）

| # | 补丁 | 目的 | 触及文件 |
|---|---|---|---|
| P1 | 增加 `/dev/susfs_guard`（misc device，写文本命令） | 让 shell 不依赖 `ksu_susfs` 也能下发 loop / uname / try_umount | 新增 `kernel/susfs_guard_ctl.c` + `Makefile` 一行 |
| P2 | `avc_audit` 路径改为「按域丢弃」而非「改 scontext」 | 消除检测器的「审计上下文被改写」判定 | `kernel/susfs_avc_spoof.c` |
| P3 | 默认关闭 `pr_info` 噪声（编译期开关） | 新 .ko 一次加载近千行日志，本身是检测面 | `kernel/*.c` 的日志宏 |

### P1 的接口设计（不用 ioctl）

内核模块里 ioctl 需要用户态配合编译，而我们希望 **shell 直接能写**，所以用 misc device + 文本协议：

```
/dev/susfs_guard   (0600 root)
  写入一行，内核解析后执行：
    loop_add <path>            → 对应 sus_path 的 loop 规则（路径稍后出现时自动隐藏）
    loop_del <path>
    set_uname <release> <version>
    try_umount <path>
  读取：返回上一行命令的结果（0 / -errno）
```

内部入口已经确认存在（同模块内直接调用，不需要导出）：

| 命令 | 上游内部函数 |
|---|---|
| path / loop | `kernel/sus_path.c:3110  void sus_path_supercall(unsigned int cmd, void __user **arg)` |
| uname | `kernel/susfs_uname.c:74  void susfs_uname_supercall(void __user **arg)` |
| try_umount | 需在 `kernel/ksu_umount_gate.c` / `sus_mount*.c` 里定位（Phase 1 第一步） |

⚠️ 这些函数吃的是 **user 指针**（内部 `copy_from_user`）。P1 的写法是：
在 `write()` 里把文本解析成 `struct st_susfs_*`，在栈上构造一个用户可寻址的临时缓冲区，
再把指针传进去；或者把 supercall 里 `copy_from_user` 之后的核心逻辑抽成 `_locked` 版本。
**这一点要在 Phase 1 先读透 `sus_path.c:3110` 再定**，不能想当然。

## 构建

上游自带 `.github/workflows/build-ddk.yml`（Android DDK）。fork 后照抄同一套：

```
矩阵     5.10 / 5.15 / 6.1 / 6.6 / 6.12 / 6.18（+ 需要的 androidNN 变体）
产物     susfs_guard_lkm-<kmi>.ko，与本模块现在的 8 个文件同名同路径
耗时     预计 30–60 分钟/次（拉内核头最慢）
```

## 下发与回退

```
module/lib/fork/<kmi>.ko      fork 版（Phase 2 起才有）
module/lib/<kmi>.ko           上游原版（保留，作为回退）
```

加载顺序：先试 fork 版 → 失败（符号预检不过 / insmod 非 0）自动回退原版，并在 `apply.log` 写明用了哪个。

## rebase 策略

- 上游发新版时：`git merge` 或重放 `patches/*.patch`，冲突只应出现在我们改过的四处
- 每个补丁都要有对应的离线测试（`tools/test_fork_*.sh`），rebase 后先跑测试再出包
- 任一补丁导致某 KMI 构建失败 → 该 KMI 先用原版，不阻塞整包发布

## Phase 计划

| Phase | 内容 | 状态 |
|---|---|---|
| 0 | vendor 源码 + 本文档 + 补丁规划 | ✅ 完成 |
| 1 | P1 补丁（`/dev/susfs_guard` 文本协议）+ shell 侧接线 + 离线测试 | 待做 |
| 2 | DDK CI 产出 8 个 KMI，进 `module/lib/fork/`，带回退 | 待做 |
| 3 | 真机验证（6.6 + 一台 5.15/6.1）后默认启用 | 待做 |