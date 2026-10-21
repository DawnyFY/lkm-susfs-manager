# 1.1.4 — 修复 1.1.3 的 CRLF 缺陷（2026-10-21）

## 背景

1.1.3 的 `load.sh` 被文本模式写入污染成 CRLF，`MODDIR` 行尾带 `\r`，
`. "$MODDIR/common.sh"` 实际请求 `.../susfs_allinone\r/common.sh` → ENOENT，
冷启动后 LKM 永远加载失败（`apply.log` 报 `[!] 加载失败，无法应用规则`）。

## 修复

1. 归一化 `module/` 下全部文本文件为 LF（二进制不受影响）。
2. `tools/build_module_zip.py` 增加构建期门禁：文本后缀出现 CR 时打印 WARN 并强制归一化后再打包。
3. 版本号 `1.1.4` / `versionCode=6`。

## 产物

| 项 | 值 |
|---|---|
| 安装包 | dist/susfs_allinone-1.1.4.zip |
| 大小 | 10,307,921 bytes |
| SHA256 | 0B87C9AD3A37AB81136CB30FFB1CD210BDB39552C984CB45CD1E49F2C12D4A1E |

## 结论

1.1.3 不可发布；1.1.4 修复后在真机冷启动 + late-load 注入下验证通过
（load.log 真加载记录、8 条规则、VERIFY_RESULT=OK）。
