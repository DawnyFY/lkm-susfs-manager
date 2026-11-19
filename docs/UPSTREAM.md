# 上游关系与许可

## 依赖关系

**1.2.6 及更早**：本项目不包含自研内核代码，SUSFS 能力全部来自上游，仓库只做集成与适配。

**1.2.7 起变更**：新增一个自研内核模块 Probe PID Guard（`lib/pid_guard/<kmi>/generic_pid_guard.ko`，GPL-2.0），
源码随仓库分发（`source/generic_pid_guard/`）。它与 SUSFS 无关、不修改上游代码，只额外提供 `getppid` 伪装能力。
SUSFS 部分仍然完全来自上游。

```
├─ simonpunk / susfs4ksu        原始 SUSFS 内核补丁（GPL-2.0）
│    └─ inforcqb / susfs4ksu-lkm    SUSFS 的 LKM 移植，产出 8 个 KMI 的 .ko + susfs_insmod
│         ├─ 上游自带 loader        susfs_guard_lkm-module-<tag>-arm64.zip（只加载，无规则）
│         └─ 本项目  ← 在本仓库     加载 + 规则下发 + WebUI + 多管理器阶段适配
├─ 本项目自研（1.2.7+）         Probe PID Guard：generic_pid_guard.ko（6 KMI，GPL-2.0）
└─ sidex15 / ksu_module_susfs    ksu_susfs 用户态工具（AGPL-3.0）
```

| 上游 | 仓库 | 版本 | 本项目使用方式 |
|---|---|---|---|
| inforcqb / susfs4ksu-lkm | https://github.com/inforcqb/susfs4ksu-for-lkm | `v2.3.0-r18.9-1` | `lib/susfs_guard_lkm-*.ko`（8）、`bin/susfs_insmod`，原样使用 |
| sidex15 / ksu_module_susfs | https://github.com/sidex15/susfs4ksu-module | `v1.5.2+_R28` | `bin/ksu_susfs_good`（回退用），原样使用 |
| simonpunk / susfs4ksu | 原始 SUSFS 项目 | — | 经 inforcqb 移植，本项目不直接引用 |

## 上游 loader 与本项目的区别

上游自带 loader：

- 只负责加载：选 KMI → `susfs_insmod` → 写日志与 module.prop 描述；
- 不写任何 SUSFS 规则；
- 依赖 `post-fs-data`；
- 没有 WebUI、规则管理、二进制回退。

本项目增量：规则下发、多管理器阶段适配、late-load 兜底、WebUI、二进制回退、启动守卫、配置导入。

## 许可证

- 本项目脚本、安装器与 WebUI：**GPL-2.0**（`LICENSE`）；
- 自研内核模块（1.2.7+）：
  - `lib/pid_guard/<kmi>/generic_pid_guard.ko` — 本项目作者，GPL-2.0，源码在 `source/generic_pid_guard/`；
- 第三方二进制：
  - `lib/susfs_guard_lkm-*.ko`、`bin/susfs_insmod` — inforcqb / `susfs4ksu-for-lkm` `v2.3.0-r18.9-1`，GPL-2.0，未修改；
  - `bin/ksu_susfs_good` — sidex15 & simonpunk / `susfs4ksu-module` `v1.5.2+_R28`，AGPL-3.0，未修改；
- 本仓库为上述组件的聚合分发，版权与许可证归原作者所有；
- 详见 `NOTICE`、`provenance.json`。

## 致谢

- **simonpunk** — SUSFS 原作者
- **inforcqb** — susfs4ksu-lkm，SUSFS 的 LKM 移植
- **sidex15** — ksu_module_susfs，`ksu_susfs` 实现
- **SukiSU Ultra 团队** — 管理器与 late-load 机制
- **旧梦一场雨**（[@hhgbmh8-ux](https://github.com/hhgbmh8-ux)）— 帮忙测试模块
- **dhc2082**（[@dhc2082](https://github.com/dhc2082)）— 1.2.8 两版 UI（冷蓝圆角 / 暖灰极简）的设计与实现
