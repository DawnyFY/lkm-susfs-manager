# LKM SUSFS管理器 v1.3.2

> 这一版只改「加载失败时能看懂发生了什么」。功能与 1.3.1 一致。

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

产物 13,224,574 B / `b98cd81d738955a5bef21a168947aac17787c0c69667602db419aef7bf85523e` / manifest `1f673976…`（40 文件）
