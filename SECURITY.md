# 安全策略

## 支持范围

仅最新 Release 版本接受安全相关的 issue。

## 报告方式

涉及以下内容时，**请勿公开开 issue**，改用 GitHub 的 Private vulnerability reporting（仓库 Security 页）或私信仓库所有者：

- 内核模块加载路径导致的提权或崩溃
- 规则下发中的越界、UAF、死锁
- 二进制被替换 / 供应链风险

一般的功能问题、兼容性问题请正常开 issue。

## 已知风险（非漏洞，属环境限制）

1. **`rmmod susfs_guard_lkm` 会导致 UAF / panic**——这是上游 LKM 的已知限制，本项目通过文档与代码规避，不通过卸载模块来“修复”。
2. **临时 root 环境下 root 不持久**——这是设备未解锁 BL 的限制，不是模块缺陷。
3. **late-load 模式下内核 `post-fs-data` 被跳过**——本项目已通过 `boot-completed` 兜底适配。

## 供应链

所有随附二进制均可在 `provenance.json` 中查到来源仓库、tag 与 sha256，且与上游 Release 资产一致（未修改）。构建可复现，可自行核对。
