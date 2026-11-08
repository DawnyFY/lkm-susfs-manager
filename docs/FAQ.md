# 常见问题

<details>
<summary><b>KMI 匹配失败 / 内核带 -dirty 怎么办</b></summary>

先跑 `ctl.sh kmiinfo`。无 Android tag 的 5.15 会尝试按 SDK 33/34 消歧；仍失败时在 WebUI 配置页填「强制指定 KMI」。自编译内核可能因符号/CFI 不匹配失败，不要反复试。
</details>

<details>
<summary><b>APatch 下状态页没有 APatch 卡片</b></summary>

卡片只在检测到 APatch / KernelPatch 时显示。KSU / Magisk 下看不到是正常的。APatch 检测特征包括 `/data/adb/ap`、`apd`；布局不同请附 `ctl.sh status` 反馈。
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
