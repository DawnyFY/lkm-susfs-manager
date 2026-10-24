#!/usr/bin/env python3
"""Fail if any shipped text file contains CR bytes."""
import sys
from pathlib import Path

SUFFIXES = {".sh", ".prop", ".js", ".css", ".html", ".json", ".txt"}
SKIP_DIRS = {".git", "dist", "__pycache__", ".github"}

base = Path(__file__).resolve().parent.parent
bad = []
for p in base.rglob("*"):
    if not p.is_file() or p.suffix not in SUFFIXES:
        continue
    if any(part in SKIP_DIRS for part in p.relative_to(base).parts):
        continue
    if b"\r" in p.read_bytes():
        bad.append(p.relative_to(base).as_posix())

if bad:
    print("CR bytes found in:")
    for f in bad:
        print("  " + f)
    sys.exit(1)
print("no CR bytes in shipped text files")