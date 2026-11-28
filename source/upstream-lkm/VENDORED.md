# 上游 LKM 源码（vendored）

| 项 | 值 |
|---|---|
| 上游仓库 | https://github.com/inforcqb/susfs4ksu-for-lkm |
| tag | `ver2.3.0` |
| commit | `0e9f088` |
| 获取方式 | `gh api repos/inforcqb/susfs4ksu-for-lkm/tarball/ver2.3.0` |
| tarball sha256 | `9eb8155f2666da3e9c1d239ad59894bc35fea7f4515054b04784290c366295d2` |
| 落地日期 | 2026-11-28 |
| 许可 | GPL-2.0（见同目录 LICENSE） |
| 文件数 | 217（`kernel/` 全部源码 + LICENSE + PROC_INTERFACES.md） |

## 与上游的差异

**当前为零差异**：本目录是原封不动的上游源码，只做了一件事 ——
删掉 `kernel/kallrecon/.github/` 与两处 `.gitignore`（避免与本仓库 CI 冲突）。

后续 fork 补丁集中记录在 `docs/FORK.md`，并在 `patches/` 下以可 rebase 的形式维护。

## 为什么把源码放进仓库

1. GPL-2.0 要求分发二进制时提供对应源码
2. fork 之后必须能对上「我们发出去的 .ko 到底由哪份源码编出来」
3. 上游 tag 被删/改名时仍有据可查

## 重建方式

```sh
gh api repos/inforcqb/susfs4ksu-for-lkm/tarball/ver2.3.0 > /tmp/src.tgz
sha256sum /tmp/src.tgz   # 应与上表一致
tar xzf /tmp/src.tgz --strip-components=1 -C source/upstream-lkm kernel LICENSE PROC_INTERFACES.md
```