#!/usr/bin/env python3
"""从 lib/*.ko 的 ELF 未定义符号生成按 KMI 的符号清单（供加载前预检）。"""
import struct, sys, pathlib

def read_elf_undef(path):
    d = pathlib.Path(path).read_bytes()
    if d[:4] != b"\x7fELF" or d[4] != 2 or d[5] != 1:
        raise ValueError("need ELF64 LE: %s" % path)
    e_shoff, = struct.unpack_from("<Q", d, 0x28)
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", d, 0x3A)
    secs = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        secs.append({
            "type": struct.unpack_from("<I", d, off + 4)[0],
            "off": struct.unpack_from("<Q", d, off + 0x18)[0],
            "size": struct.unpack_from("<Q", d, off + 0x20)[0],
            "link": struct.unpack_from("<I", d, off + 0x28)[0],
            "entsize": struct.unpack_from("<Q", d, off + 0x38)[0],
        })
    out = set()
    for s in secs:
        if s["type"] not in (2, 11):
            continue
        entsize = s["entsize"] or 24
        strtab = secs[s["link"]]["off"] if s["link"] < len(secs) else 0
        for i in range(s["size"] // entsize):
            o = s["off"] + i * entsize
            nm, = struct.unpack_from("<I", d, o)
            shndx, = struct.unpack_from("<H", d, o + 6)
            if shndx != 0 or nm == 0:
                continue
            end = d.index(b"\x00", strtab + nm)
            out.add(d[strtab + nm:end].decode("utf-8", "replace"))
    return sorted(out)

def main():
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    lib = root / "module/lib"
    out_dir = lib / "symbols"
    out_dir.mkdir(parents=True, exist_ok=True)
    skip = {"_GLOBAL_OFFSET_TABLE_"}
    total = 0
    for ko in sorted(lib.glob("susfs_guard_lkm-*.ko")):
        kmi = ko.stem.replace("susfs_guard_lkm-", "")
        syms = [s for s in read_elf_undef(ko)
                if s not in skip and not s.startswith("__gnu_mcount")]
        # 必须显式 newline="\n"：write_text 在 Windows 上会把 \n 翻成 \r\n，
        # 生成的清单在设备上 grep -x 永远匹配不上（真机踩过：116 个符号全报缺失）
        with open(out_dir / (kmi + ".symbols"), "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(syms) + "\n")
        print("%-16s %3d symbols" % (kmi, len(syms)))
        total += 1
    print("KMI 清单: %d 份 -> %s" % (total, out_dir))

if __name__ == "__main__":
    main()