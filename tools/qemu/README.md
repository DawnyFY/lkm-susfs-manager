# QEMU 内核侧回归测试

在 QEMU 里启动一棵**与设备同版本号**的 arm64 内核，跑真实的内核模块，验证
`/proc/susfs_path` 的 `add_loop` 语义（fork 补丁 P1）。

用途：内核侧改动不做真机试错 —— 尤其是「按 kallsyms 改内存」的模块，内核版本不匹配时会直接把机器打崩。

## 验证的三件事

| 断言 | 看哪里 |
|---|---|
| 路径不存在时规则能建起来 | 节点里出现 `dev=0 ino=0 (pending)`，`pend: ... last-rc=-2` |
| 内核会后台重试并解析 | `pend: passes/ticks 递增`，最终 `last-rc=0`、`dirent: pending=0` |
| 解析后对普通应用隐藏 | 以 `uid=10123` 视角 `opendir` 看不到、`access` 返回 ENOENT |

## 前置条件

```
1. 内核树（例：/root/kb/6.6），VERSION 改成设备 uname -r 对应的版本，
   LOCALVERSION_AUTO 关掉、删掉 .git（否则 vermagic 会带 -g<sha>-dirty 或超 64 字符）
2. 该内核已编译出 arch/arm64/boot/Image
3. 被测模块 .ko（默认 $KDIR/../up2/susfs_guard_lkm.ko）
4. WSL 里装了 qemu-system-arm、cpio；NDK 用于静态编译 init
```

## EXPORT_SYMBOL：测试内核必须做的临时改动

上游模块有 5 个符号不走导出表，而是运行时用 kallsyms 解析（`symbol_resolver.c`），
由它的专用加载器 `susfs_insmod` 在用户态做重定位。initramfs 里没有 bionic，跑不了那个加载器，
所以测试内核需要临时导出这 5 个符号：

```c
/* mm/init-mm.c         */ EXPORT_SYMBOL(init_mm);
/* arch/arm64/mm/mmu.c  */ EXPORT_SYMBOL(__set_fixmap);
/* mm/maccess.c         */ EXPORT_SYMBOL_GPL(copy_to_kernel_nofault);
/* kernel/task_work.c   */ EXPORT_SYMBOL(task_work_add);
/* fs/proc/bootconfig.c */ char *saved_boot_config;  EXPORT_SYMBOL(saved_boot_config);
                        /* 原本是 static，需要先去掉 static */
```

**这些改动只用于测试，不要进发行版内核。**

## 运行

```sh
KDIR=/root/kb/6.6 \
MODULE_KO=/root/kb/up2/susfs_guard_lkm.ko \
sh tools/qemu/run.sh
```

`run.sh` 会：编 `init.c`（NDK 静态 aarch64）→ 打 initramfs（含模块）→ 起 QEMU → 只打印断言行。

## 预期输出

```
[init] finit_module rc=0
[init] 目标存在? 否
[init] 写入 "add_loop /tmp/loopdir/secret" -> 成功
    dirent: pending=1
    pend: passes=1 ticks=0 walks=0 lost=0 last-rc=-2
    path=/tmp/loopdir/secret  dev=0 ino=0  (pending: no inode yet)
[init] 已创建 /tmp/loopdir/secret
    dirent: pending=0
    pend: passes=2 ticks=1 walks=1 lost=0 last-rc=0
[init] root 视角: 目录列表可见 1 | access 可见
[app uid=10123] 目录列表可见: 否 | access: ENOENT
```

root 可见是设计如此（`hide_from_apps=1`），所以断言必须用普通 uid 跑。

## 已知限制

- QEMU 内核用的是 AOSP common 源码 + 设备版本号，**不是设备厂商内核本身**；
  只能验证模块逻辑，不能替代真机兼容性验证
- initramfs 里没有 Android 运行时，依赖 bionic 的工具（如 `susfs_insmod`）无法运行