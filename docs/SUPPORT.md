# 反馈与支持

## 提交前请确认

1. 读过 README 与 [安全与免责](SAFETY.md)；
2. 不是以下已知情况：
   - 临时 root 重启后需要重新注入（环境限制）；
   - 冷启动后 Zygisk 未注入（先热重启再测）；
   - KMI 不在 [支持列表](KMI.md)；
   - APatch 默认不加载 LKM（需显式放行）。
3. 已准备 `load.log`、`apply.log`、`ctl.sh status` 输出。

## 渠道

| 情况 | 去哪 |
|---|---|
| 模块加载失败、规则没生效、WebUI 报错 | [提交问题](https://github.com/DawnyFY/lkm-susfs-manager/issues/new?template=bug_report.yml) |
| 功能建议 | [功能建议](https://github.com/DawnyFY/lkm-susfs-manager/issues/new?template=feature_request.yml) |
| 使用经验 / 配置分享 | [Discussions](https://github.com/DawnyFY/lkm-susfs-manager/discussions) |
| 内核模块崩溃 / `.ko` 兼容性 | 上游 [inforcqb/susfs4ksu-lkm](https://github.com/inforcqb/susfs4ksu-lkm/issues) |
| `ksu_susfs` 行为问题 | 上游 [sidex15/ksu_module_susfs](https://github.com/sidex15/ksu_module_susfs/issues) |
| 安全漏洞 | 见 `SECURITY.md`，请勿公开开 issue |

## 最小信息

```
设备型号：
Android / 内核版本（uname -r）：
管理器与版本：
root 类型：临时（未解锁 BL）/ 永久（已解锁 BL）
模块版本：
现象：
load.log / apply.log / ctl.sh status：
```

APatch 反馈额外附：

- KernelPatch/kpimg 版本；
- `kernelpatch_kernel` / `allow_lkm` 状态；
- 是否内核已内置 SUSFS；
- 是否使用 APatch Manager 安装。
