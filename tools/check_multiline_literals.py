#!/usr/bin/env python3
"""门禁：shell 脚本里禁止出现「跨行字面量」写法。

背景（两次真实事故）：
  1) printf '%s<真换行>' 把格式串拆成两行 —— 功能等价但极脆弱；
  2) _CFG_CR=$(printf '<真换行>') —— 命令替换吃掉尾随换行，变量恒为空，
     CR 裁剪整条失效，CRLF 配置里所有开关都被当成「不等于 1」。

判定：某行以未闭合的引号结尾，且下一行只由「闭合引号 + 可选右括号」构成。
"""
import glob
import io
import re
import sys

# 行尾是未闭合引号（引号前不能有反斜杠转义）
OPEN_TAIL = re.compile(r"(?<!\\)(['\"])[ \t]*$")
# 下一行只有闭合引号，可能跟 ) 或 ))
CLOSE_ONLY = re.compile(r"^[ \t]*(\"|')[ \t]*\){0,2}[ \t]*$")

TARGETS = ["module/*.sh", "module/*/*.sh"]


def scan(paths):
    hits = []
    for path in sorted({p for pattern in paths for p in glob.glob(pattern)}):
        lines = io.open(path, encoding="utf-8", errors="replace").read().split("\n")
        for i, line in enumerate(lines):
            m = OPEN_TAIL.search(line)
            if not m:
                continue
            nxt = lines[i + 1] if i + 1 < len(lines) else ""
            if CLOSE_ONLY.match(nxt):
                hits.append((path, i + 1, line.strip()[:72], nxt.strip()[:24]))
    return hits


def main():
    hits = scan(TARGETS)
    if hits:
        for path, ln, cur, nxt in hits:
            print(f"FAIL  {path}:{ln}: {cur}  ->  {nxt}")
        print(f"跨行字面量 {len(hits)} 处：请改成单行写法（例如 printf '\\r' 而不是真实的控制字符）")
        return 1
    print("OK: 未发现跨行字面量")
    return 0


if __name__ == "__main__":
    sys.exit(main())
