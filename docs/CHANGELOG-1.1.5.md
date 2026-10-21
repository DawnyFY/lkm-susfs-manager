# 1.1.5 — 更名与 WebUI 图标移除（2026-10-21）

## 改动

| # | 位置 | 内容 |
|---|---|---|
| 1 | module.prop | 显示名 SUSFS 管理器 → LKM SUSFS管理器；version=1.1.5 / versionCode=7（模块 ID 仍为 susfs_allinone，升级与配置继承不受影响） |
| 2 | webroot/index.html | title、页头 h1、关于页 h2 同步为新名字 |
| 3 | webroot/index.html | 移除页头图标 div.logo（蓝色 S 方标） |
| 4 | webroot/style.css | 删除 .logo 基础样式与窄屏覆盖块（2 处） |
| 5 | webroot/app.js | 配置模板首行注释同步为新名字 |
| 6 | tools/check_zip.py | 名称/版本断言与默认包名改为 1.1.5 |

## 产物

| 项 | 值 |
|---|---|
| 安装包 | dist/susfs_allinone-1.1.5.zip |
| 大小 | 10,307,807 bytes |
| SHA256 | 4E20DD0C1FBE116C790A5C80FEB1BD59F69CD584B55322F4970FD3C8D3E80FF8 |
| check_zip.py | OK |
| check_license_compliance.py | RESULT: OK |

## 注意

- 名称变了、ID 没变，模块仍是同一个（配置、规则、禁用状态都继承）。
- 1.1.3 制品有 CRLF 缺陷不可发布；1.1.4 可发布；本版只是改名与 UI 调整。
