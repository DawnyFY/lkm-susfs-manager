# 1.1.6 — 第三方署名补全与可复现构建（2026-10-21）

## 改动

| # | 位置 | 内容 |
|---|---|---|
| 1 | NOTICE | 页头改为新显示名；LKM 组件补注"原作者 simonpunk（SUSFS / susfs4ksu，GPL-2.0），LKM 移植与维护 inforcqb" |
| 2 | provenance.json | 增加 name 字段；LKM 组件增加 original_author 说明 |
| 3 | tools/build_module_zip.py | 改为固定 1980-01-01 时间戳 + 固定权限位，ZIP 可字节复现（两次构建 sha256 一致） |
| 4 | module.prop | version=1.1.6 / versionCode=8 |

## 产物

| 项 | 值 |
|---|---|
| 安装包 | dist/susfs_allinone-1.1.6.zip |
| 大小 | 10,307,959 bytes |
| SHA256 | 28E31565E3ABD7A3942A1D7489F3B504E8F029214660C03DB242FF311E7E00F6 |
| 复现性 | 同一源码两次构建 sha256 完全相同 |
| check_zip.py | OK |
| check_license_compliance.py | RESULT: OK |

## 说明

- 功能与 1.1.5 完全相同，仅署名与构建方式变化。
- GPLv2 组件的版权署名现在覆盖到 SUSFS 原始作者，符合"保留原作者署名"的要求。
