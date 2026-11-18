# 常见问题

<details>
<summary><b>PID 隐藏（Probe PID Guard）怎么关，关了会怎样</b></summary>

WebUI「PID 隐藏」页把开关关掉即可，保存即生效：立即 `rmmod`，并从 `/proc/susfs_hide_modules` 撤掉名字，不需要重启。
也可以在 `config/pid_guard.conf` 里把 `enabled=1` 改成 `0`，下次 apply 时卸载。

它只影响 `getppid` 伪装，不影响任何 SUSFS 规则；关掉后状态卡会显示「已关闭」、最近结果 `unloaded`。

装完想看是否真的生效：状态卡「内核模块」应为已加载、「内核可见」应为否（`/proc/modules` 命中 0）、
「隐藏列表」应为已隐藏；命令行为 `ctl.sh status | grep pid_guard` 与 `ls /sys/module/generic_pid_guard`。
</details>

<details>
<summary><b>PID 隐藏保存后提示「配置无效」</b></summary>

`pid_guard.conf` 只接受受限字符：字母数字与 `_,.:/@+-`，comm 允许 `*` 但只能作后缀。常见触发点：

- 「目标 comm」里写了空格（例如 `probe-*, canProbe*`）——空格会被拒绝，因为旧实现下空格会让整行静默失效
- 写了裸 `*` 想匹配全部进程——内核侧空前缀判定为不匹配，配置侧直接拒绝
- `target_uids` 写了非数字（如 `abc`）、两端带 `-`、或 `1-2-3` 这种多段
- `target_uids` 与 `target_comms` 同时为空

被拒绝时旧配置不会被覆盖，`load.log` 会记 `配置被拒绝：...`，状态码为 `bad_conf`。
</details>

<details>
<summary><b>KMI 匹配失败 / 内核带 -dirty 怎么办</b></summary>

先跑 `ctl.sh kmiinfo`。无 Android tag 的 5.15 会尝试按 SDK 33/34 消歧；仍失败时在 WebUI 配置页填「强制指定 KMI」。自编译内核可能因符号/CFI 不匹配失败，不要反复试。
</details>

<details>
<summary><b>APatch 下状态页没有 APatch 卡片</b></summary>

卡片只在检测到 APatch / KernelPatch 时显示。KSU / Magisk 下看不到是正常的。APatch 判定只认运行态/可执行体（`pidof apd`、`/data/adb/apd`、`ap/bin/apd`）；仅残留 `/data/adb/ap` 或 `package_config` 不会再触发 APatch 保护。布局不同请附 `ctl.sh status` 反馈。
</details>

<details>
<summary><b>APatch 下 LKM 不加载</b></summary>

这是默认安全策略。内核已内置 SUSFS 时不需要 LKM；没有内置且接受风险时，执行 `ctl.sh allow_lkm` 或 WebUI 放行，再手动 `load.sh manual`。放行前备份并确认恢复手段。
</details>

<details>
<summary><b>Magisk 下规则没生效</b></summary>

Magisk 没有 `boot-completed`，规则在 `service`（late_start）阶段应用。先看 `apply.log` 与 WebUI 状态；本版本未做 Magisk 真机冷启动验证。
</details>

<details>
<summary><b>会不会覆盖管理器自带的 ksu_susfs</b></summary>

不会。优先使用管理器自带二进制，仅在无法通信时回退到模块内置备份，且不覆盖原文件。
</details>

<details>
<summary><b>用 NeoZygisk 时开机 zygote 循环 / 模块失效</b></summary>

外部反馈：NeoZygisk v2.4 + r18.8 在默认隐藏 `/data/adb` 时，zygote 可能反复重启。请删除 `config/sus_path.txt` 中的 `/data/adb`（只能删除整行；模块/SUSFS 不支持从已隐藏父目录排除 `/data/adb/neozygisk`），再重新应用规则。本环境使用 Zygisk Next，未复现；详见 `docs/RELEASE_NOTES_122.md`。
</details>

<details>
<summary><b>冷启动后 Zygisk / LSPosed 异常</b></summary>

临时 root 冷启动时 Zygisk 可能没在 zygote 前就位；这是环境时序，不是模块问题。完成 root 后热重启再测。模块本身只负责 SUSFS LKM。
</details>

<details>
<summary><b>模块显示未加载</b></summary>

先看 `load.log`：KMI 不匹配、`.ko` 与内核不兼容、没有 root 会话、APatch 未放行都可能。可执行一次模块 Action 手动加载验证。
</details>

<details>
<summary><b>加载错了怎么恢复</b></summary>

禁用模块后重启；不要执行 `rmmod susfs_guard_lkm`。若已 bootloop，用管理器禁用模块或恢复备份。
</details>
