# 1.3.3 计划：自研 LKM 的 ioctl 通道（补齐节点后端缺口）

> 1.3.2 不做这件事。1.3.2 冻结在「节点后端 + loop 退化」，本文件记录 1.3.3 的交付物。

## 为什么要做

1.3.2 的第三级回退（`NODE_ONLY`）只能覆盖内核**已有 proc 节点**的能力：

| 能力 | 节点后端 | 原因 |
|---|---|---|
| sus_path 增删 | 支持 | `/proc/susfs_path` 接受 `add/del` |
| hide_mounts | 支持 | `/proc/susfs_hide_mounts` |
| sus_map | 支持 | `/proc/susfs_map` |
| hide_modules | 支持 | `/proc/susfs_hide_modules` |
| **sus_path_loop** | 退化 | 需要 `add_sus_path_loop`，只有 ioctl 有 |
| **uname / cmdline 伪装** | 缺失 | 需要 ioctl |
| **try_umount** | 缺失 | 需要 ioctl；且日志里常见「本内核未实现 try_umount」 |

`ksu_susfs` 二进制 ABI 与内核不匹配时（服务器日志里最常见的失败形态），这三项现在只能放弃。

## 目标

给自研内核模块加一个字符设备，用 ioctl 直接实现上面三项，**不再依赖 `ksu_susfs` 二进制**。

```
/dev/susfs_guard   设备节点（misc device，权限 0600 root）
  ioctl 命令（沿用 ksu_susfs 的子集语义，便于复用现有参数解析）
    SUSFS_GUARD_ADD_LOOP_PATH   struct { char path[PATH_MAX]; }
    SUSFS_GUARD_SET_UNAME       struct { char release[65]; char version[65]; }
    SUSFS_GUARD_TRY_UMOUNT      struct { char path[PATH_MAX]; }
```

## 交付物

1. `source/generic_pid_guard/` 扩成双功能（pid 伪装 + 控制设备），或新增
   `source/susfs_guard_ctl/`（更干净：pid_guard 保持单一职责）
2. 6 个 KMI 的交叉编译产物（5.10 / 5.15 / 6.1 / 6.6 / 6.12 / 6.18）
3. CI workflow：`tools/build-lkm.yml`，矩阵编译 + 产物校验（ELF 架构、符号预检对齐）
4. shell 侧：`common.sh` 增加 `guard_ioctl_*` 封装，`apply.sh` 的 loop/uname/try_umount
   三段改为「CLI → 节点 → ioctl」三级回退
5. `tools/test_guard_ioctl.sh`：离线夹具 + 真机 ioctl 往返（需要至少 2 个 KMI 的真机）

## 验收标准

- `NODE_ONLY=1` 时 `sus_path_loop` 真的能注册 pending 规则（`/proc/susfs_path` 出现 `pending`）
- `spoof_uname` 在节点后端下生效（应用态读 `uname -r` 得到伪装值）
- `try_umount` 在节点后端下生效
- 符号预检：新 .ko 的 symbols 清单与 8 个 KMI 一一对应，加载前 0 缺失
- 现有 59 个离线测试 + 真机回归全绿；不得回退 1.3.2 已有的三级回退行为

## 前置条件 / 风险

| 项 | 说明 |
|---|---|
| 交叉编译环境 | 当前开发机无 NDK/clang，必须走 CI（ubuntu + `aarch64-linux-gnu-gcc` 或 Android NDK r26） |
| 内核头文件 | 需要各 KMI 的 `common/` 与 `arch/arm64/` 头（可复用 inforcqb 仓库的构建脚本） |
| 模块签名 | 不签名的 .ko 在 `CONFIG_MODULE_SIG_FORCE=y` 的内核上必失败（errno 61），这是既有限制，不做绕签名 |
| ABI 稳定性 | ioctl 结构体布局一旦发布不能改（用 `_IOR/_IOW` + 固定字段），后续只加不改 |
| 测试成本 | 每个 KMI 都要真机或 QEMU 验证；至少 6.6（现有设备）+ 5.15/6.1（需借测） |

## 与 1.3.2 的边界

- 1.3.2 已有：三级回退、loop 退化（路径已存在时按普通 sus_path 下发）、符号预检、
  `suggest_kmi`、`doctor`、掉线看护
- 1.3.3 才做：ioctl 设备、交叉编译、loop/uname/try_umount 的真实节点通道
- **不把 ioctl 的半成品放进 1.3.2**：没有 .ko 的部分等于死代码，审计已经踩过一次这个坑