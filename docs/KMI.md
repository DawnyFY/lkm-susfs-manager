# KMI 匹配

## 支持表

| KMI | 内核版本 | 状态 |
|---|---|---|
| `android12-5.10` | 5.10 | 打包，未实机验证 |
| `android13-5.10` | 5.10 | 打包，未实机验证 |
| `android13-5.15` | 5.15 | 打包，未实机验证 |
| `android14-5.15` | 5.15 | 打包，未实机验证 |
| `android14-6.1` | 6.1 | 打包，未实机验证 |
| `android15-6.6` | 6.6 | **已实机验证（KSU 系）** |
| `android16-6.12` | 6.12 | 打包，未实机验证 |
| `android17-6.18` | 6.18 | 打包，未实机验证 |

`.ko` 来自上游 `inforcqb/susfs4ksu-lkm` `v2.3.0-r18.8`，未修改。

## 匹配顺序

1. 内核版本字符串带 `-androidXX-<kver>`：直接匹配；
2. 无 tag、但版本唯一（如 6.1 / 6.6 / 6.12 / 6.18）：匹配对应 KMI；
3. 无 tag 的共享 5.10 / 5.15：尝试按 SDK 消歧（SDK 33/34 → android13/14-5.15），仅在对应 `.ko` 已打包时采用；
4. 仍无法唯一确定：拒绝加载，不猜测。

优先使用 `/proc/version`，回退开机真实内核快照，最后才用 `osrelease`。

## dirty / 自编译内核

- 带 `-dirty` 不等于一定不兼容，但符号/CFI/KMI 差异风险高；
- 不要反复试错加载；失败会写 `load.log`；
- 确认不了 KMI 时用「强制指定 KMI」，并准备回滚。

## 手动指定

WebUI 配置页填写「强制指定 KMI」，例如 `android14-5.15`，保存后点「加载并应用」。

## 诊断

```sh
su -c "sh /data/adb/modules/susfs_allinone/ctl.sh kmiinfo"
```

输出包含 osrelease、matched、packaged、guessed、内核配置等。常见失败原因见 [FAQ](FAQ.md)。
