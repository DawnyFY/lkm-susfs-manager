# LKM SUSFS管理器 v1.3.1

> 这一版只做一件事：**许可证改为分层许可**。功能与 1.3.0 完全相同。

## 为什么改

1.3.0 及之前整包标注 GPL-2.0。但包里既有我们自己的用户态代码，也有**内核模块**
（`susfs_guard_lkm*.ko` 来自上游、`generic_pid_guard.ko` 自研）。
内核模块是 Linux 内核（GPL-2.0-only）的衍生作品，只能与内核许可兼容 ——
而 GPLv2-only 与 GPLv3 不兼容，所以不能把整包改成 GPLv3。

拆分后各归各位：

| 部分 | 许可证 | 全文 |
|---|---|---|
| 本项目自有代码：脚本 / 安装器 / WebUI / tools | **GPL-3.0-only** | `LICENSE` |
| 自研内核模块 `generic_pid_guard.ko` | GPL-2.0-only | `LICENSE-GPL-2.0` |
| 上游内核模块 `susfs_guard_lkm-*.ko`、`bin/susfs_insmod` | GPL-2.0 | `LICENSE-GPL-2.0` |
| 上游用户态工具 `bin/ksu_susfs_good` | AGPL-3.0 | `LICENSE-AGPL-3.0` |

整体属于**聚合分发**（mere aggregation）：本项目自有代码的 GPL-3.0 授权不延伸到上述内核模块与第三方二进制，
GPL-2.0 / AGPL-3.0 组件的条款也不限制本项目自有代码。

## 具体改动

- `LICENSE` 换成 GNU GPL v3.0 全文（35,149 B）
- 新增 `LICENSE-GPL-2.0`（GNU GPL v2.0 全文，给内核模块与上游 `.ko` 用）
- `NOTICE` 重写为分层声明：逐组件写清文件、作者、仓库、Tag、许可证、是否修改、如何取得源码
- 25 个源码文件的 SPDX 头：`GPL-2.0-only` → `GPL-3.0-only`
- `README` 许可章节改为分层表格 + 说明为什么不跟随 GPLv3
- 合规门禁 `check_license_compliance.py` 改为校验：GPLv3 全文、`LICENSE-GPL-2.0` 存在且为 v2 全文、
  `NOTICE` 含 `GPL-3.0-only` 与分层说明

## 升级影响

- **功能、配置、状态字段与 1.3.0 完全一致**，只是版本号前进一位（`1.3.1` / `versionCode 23`），
  以便已经装了 1.3.0 的用户能被管理器提示更新
- 覆盖安装保留 `config/` 与 `state/`
- 二次分发者请注意：如果你的打包方式把 `.ko` 与本项目代码视为单一作品，需按 GPLv2 处理那些内核模块

## 验证

- 离线 **55/55**、Vitest **56/56**、vue-tsc 0、门禁 **6/6**、`I18N_OK keys=197`
- 合规门禁在包内检出：`LICENSE`（GPLv3）、`LICENSE-GPL-2.0`（GPLv2）、`LICENSE-AGPL-3.0`、`NOTICE`
- 产物 13,221,351 B / `8b65688a…` / manifest `36035d74…`（40 个文件）
