# Probe PID Guard — 内核模块源码

`module/lib/pid_guard/<kmi>/generic_pid_guard.ko` 的对应源码。GPL-2.0，随模块一起分发；
本目录即为 GPL-2.0 意义上「可获取的完整对应源码」。

## 文件

| 文件 | 说明 |
|---|---|
| `generic_pid_guard.c` | 唯一源文件（kretprobe `__arm64_sys_getppid`，按 UID 范围 / comm 前缀匹配后改写返回值） |
| `generic_pid_guard.lds` | 链接脚本 |
| `Makefile` | `obj-m := generic_pid_guard.o` |
| `build_one.sh` | 在 DDK 容器里编一个 KMI：`TARGET=<kdir> OUTDIR=<kmi> bash build_one.sh` |
| `build_inside.sh` | 单次编译（默认 6.18，可用 `KDIR=` 覆盖） |

## 编译

```bash
docker run --rm -v "$PWD:/work" -w /work \
  ghcr.nju.edu.cn/ylarod/ddk-min:android15-6.6-20260828 \
  bash -lc 'TARGET=/opt/ddk/kdir/android15-6.6 OUTDIR=6.6 bash build_one.sh'
```

## 产物

| KMI | 产物大小 | sha256 |
|---|---|---|
| 5.10 | 259,432 | `cd5d5351014e7f8ba63b8797851f1cc1dfcec899ce4db54630d0d4b3d88c2781` |
| 5.15 | 264,920 | `5cc5b69b4298b9f89bb45d18b6cb8528c616198680feef997310033bff27e06e` |
| 6.1 | 268,776 | `c36f084d4189a0d846945c38adaaf66ddc1248a2d88a78a4bac3dc8230bc2148` |
| 6.6 | 187,640 | `5878c01a484b528f18ab432b57f01da46848be9c95a24dcab329b42008608149` |
| 6.12 | 199,024 | `3fb239abc96f12134c3b83e4c1b125460502b123fa1e8a573f887cf3337fc0dd` |
| 6.18 | 209,776 | `0973a7578089e0beb389010bf41a8ddaec4fc140d922638f51cafb030b8f6512` |

DDK 镜像标签：`android12-5.10-20260828` / `android13-5.15-20260828` / `android14-6.1-20260828` /
`android15-6.6-20260828` / `android16-6.12-20260828` / `android17-6.18-20260828`。

## 安全相关约束（不要改回去）

- 三个 `module_param_string(..., 0440)`：目标 UID/comm 清单是检测面信息，sysfs 不能对普通进程可读。
- `comm_prefix()` 对空前缀返回 `false`：裸 `*` 会命中所有进程，等于全系统伪装 getppid。
- 只接受 `insmod` 期参数，没有运行时写入口，因此 0440 不影响配置能力（改配置由 `pid_guard.sh` 重载）。
