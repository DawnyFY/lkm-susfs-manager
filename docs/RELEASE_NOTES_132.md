# LKM SUSFS管理器 v1.3.2

> 这一版以「加载失败时能看懂发生了什么」为主，另外修了 PID 命中统计、锁归属与若干门禁，
> 并新增符号预检 / suggest_kmi / doctor / 掉线看护（默认关）。功能集合与 1.3.1 **不同**。


## 1.3.2：移除 1.3.0 引入的 AVC LKM 参数通道

1.3.0 为了让官方 KernelSU 也能开 `avc_spoof`，加了一条「直接写 LKM 参数
`/sys/module/susfs_guard_lkm/parameters/avc_su_ctx`」的通道（提交 `697e2da`），
并把出厂默认改成 `avc_spoof=1`（提交 `2ab496d`）。

真机两轮实测证明这条通道**开了比不开更糟**：

| 状态 | 检测器结论 |
|---|---|
| `avc_spoof=1`（参数通道生效） | **危险 1** —— 「SELinux 审计记录被改写 / 审计运行异常 / 审计上下文被改写」 |
| `avc_spoof=0` | 危险 0、可疑 1（只剩 ADB 调试那条信息级） |

因此 1.3.2：

- **移除** LKM 参数通道（不再写 `avc_su_ctx`），只保留 `ksu_susfs` 命令与 `/proc/susfs_avc_spoof` 节点两条
- **出厂默认改回 `avc_spoof=0`**
- **升级时一次性迁移**：老配置里的 `avc_spoof=1` 自动改成 0（只在首次 apply 做一次，
  之后用户手动再开不会被改；哨兵文件 `state/migrated_avc_132`）
- **清理残留**：若 LKM 参数当前仍停在伪装值（老版本留下的），apply 时自动还原成原值
- 想继续用的人可以自己开，但会看到「会被判审计被改写」的提示
## 1.3.2 新增（本轮）

### 符号级预检
打包 8 份 `module/lib/symbols/<KMI>.symbols`（由 `tools/gen_lkm_symbols.py` 从 .ko 的 ELF 未定义符号生成，113~124 条）。
`load.sh` 在 insmod 之前用 `/proc/kallsyms` 逐字段精确比对，缺符号时直接列出前 5 个名字，
而不是等 errno 14/22 再猜。

### KMI 建议器
`ctl.sh suggest_kmi` 按主版本 + 内核串里的 `androidNN` 选出最接近的打包 KMI，并给出可直接复制的 `force_kmi=` 行；
`diag_load_failure` 在 errno 14/22 时提示同版本其它 KMI 可试，在 2/8/38/61 时给最接近的 KMI 建议。

### doctor（规则健康度自检）
`ctl.sh doctor` 检查六类问题：sus_path 不存在/非绝对/重复/落在检测 App 目录、sus_path_loop 里路径已存在、
hide_modules 当前不存在、pid_guard 空规则与 `*` 位置、挂载前缀未以 `/` 开头。干净配置不误报。

### LKM 掉线看护（默认关闭）
`config.ini` 的 `watchdog_minutes`（默认 0）设为非 0 时，`service.sh` 低频检查 `/sys/module/susfs_guard_lkm`
与 `/proc/susfs_path`，掉线则记日志并重跑 apply。

### 节点后端 loop 退化
`NODE_ONLY=1` 且路径已存在时，`sus_path_loop` 条目按普通 `sus_path` 下发，不再整条判失败。

### PID 隐藏统计修复
`count_matched` 旧实现恒返回 0（读 status 的方式有 bug）；改为 `stat -c %u` + 30 秒缓存，
卸载/改参数时清缓存；PID 页面新增「命中进程」与 0 命中提示。

### 锁归属二次确认
`lock_acquire` 写完 pid 后回读确认等于 `$$` 才算抢到，堵住并发双持有。
TTL 语义是「持有者承诺的最长持锁时间」，超过即回收；三处取值按各自最长持锁时间设定（apply 180s /
set_config 180s / set_bundle 300s），双持有风险由 pid 归属回读兜住。
## 为什么做这个

服务器失败日志里 `[!] LKM 加载失败，请查看日志 (rc=N)` 是最常见的一条，
但日志**不给任何原因**。用户只能贴一句"加载内核失败"来问，我们也没法判断是
KMI 不对、签名强制、还是跟别的模块打架。

## 新增：加载失败共存诊断

失败时按顺序输出：

- **errno 解释**：1 EPERM / 12 ENOMEM / 13 EACCES / 14 EFAULT / 16 EBUSY /
  17 EEXIST / 22 EINVAL / 38 ENOSYS / 61 ENODATA
- **内核里已有的相关模块**：优先 `/sys/module`，回退 `/proc/modules`
  （hide_modules 只过滤 /proc/modules 与 kallsyms，前者会被我们自己的隐藏挡掉）
- **其它会加载内核模块的模块**：扫 `/data/adb/modules/*`，列出带 `.ko` 且未停用的
- **并发加载**：检测同时进行的 insmod / ksud
- **内核日志关键行**：unknown symbol / disagrees about version / module verification failed /
  Key was rejected / exec format error / version magic，并按内容给出结论
- **加载限制实测**（errno 1/61）：`modules_disabled`、`lockdown`、
  `CONFIG_MODULES` / `CONFIG_MODULE_SIG(_FORCE|_ALL)`

失败消息本身也带含义：

```
[!] …（errno 14 · EFAULT（模块镜像与内核结构不匹配：多半是 KMI/布局不对））(rc=N)
```

## 新增：加载前提示

- 内核里已有同族模块时，先提示「本次可能撞 EEXIST/EBUSY，失败时会打印诊断」
- `CONFIG_MODULE_SIG_FORCE=y` 时预告「未签名 LKM 大概率失败（errno 61/1），
  只能改用内置 SUSFS 的内核」

## 来自服务器日志的印证

2026-11-25 拉取的 196 条日志中，1.3.0/1.3.1 上的失败**全部**是同一形态：

```
susfs_insmod: init_module failed: errno 61
内核 5.15.194-android13-8-00019-gf4321180a397-ab15212794（KernelSU）
```

即该内核开启了强制模块签名。1.3.2 会在加载前就提示这一点，并在失败时直接给出结论，
不用再让用户猜。

## 升级影响

- 功能、配置、状态字段不变；覆盖安装保留 `config/` 与 `state/`
- 版本 1.3.2 / versionCode 24

## 验证

- 离线 56/56（新增 `test_load_diag.sh` 17 条）、Vitest 56/56、门禁 6/6
- 真机（6.6.77 / KernelSU）：诊断链路实测通过；
  本机 `CONFIG_MODULE_SIG=y` 但无 `FORCE`，所以加载正常 —— 正好验证了判定条件

产物 18,677,630 B / `be6718a73894c2196670df9d363c03916aa93b03ac6a4f5dcb518012fe767094` / manifest `59c25beb…`（60 文件）

## 附带：sus_path 里「不存在的路径」不再计入规则失败

服务器日志里出现「30 条规则 / 70 条失败」这类状态：用户把游戏反作弊的临时文件写进
sus_path，路径本来就不存在，于是每次 apply 都记一次失败、逐日累积。

现在这类条目单独计数并提示：



apply 结果不再因此降级为 partial；真有内核拒绝时仍会照常报失败。

产物 18,677,630 B / `be6718a73894c2196670df9d363c03916aa93b03ac6a4f5dcb518012fe767094` / manifest `59c25beb…`（60 文件）
