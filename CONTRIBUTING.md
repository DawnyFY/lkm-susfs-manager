# 贡献指南

感谢关注 LKM SUSFS管理器。

## 报告问题

请附上以下信息，否则很难定位：

1. 设备型号、Android 版本、内核版本（`uname -r`）
2. 管理器及版本（SukiSU / KernelSU / ReSukiSU / KernelSU Next）
3. 是否临时 root、是否解锁 BL
4. 模块 `load.log` 与 `apply.log`（模块目录下）
5. `ksud module list` 中本模块的那一段

## 提交代码

1. Fork 本仓库并新建分支
2. 修改后本地跑通三项校验：

```sh
python tools/build_module_zip.py
python tools/check_zip.py
python tools/check_license_compliance.py
```

3. 若改动了 shell 脚本，请确认**没有 CRLF**（否则设备上 `$MODDIR` 会带 `\r` 导致路径失效）：

```sh
python -c "import pathlib,sys; [print(p, p.read_bytes().count(b'\r')) for p in pathlib.Path('.').rglob('*.sh')]"
```

4. 提交 PR，说明改动目的与测试情况

## 第三方二进制

`lib/*.ko` 与 `bin/*` 来自上游项目，**不接受直接替换二进制**。若确需更新：

- 必须同步更新 `provenance.json` 中的哈希与来源
- 必须在 `NOTICE` 中说明是否修改
- 必须能通过 `tools/check_license_compliance.py`

## 许可证

提交的代码默认按 GPL-2.0 授权。请确保你有权提交该代码。
