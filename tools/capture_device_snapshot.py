#!/usr/bin/env python3
"""Capture a read-only snapshot of the connected device.

Usage:
    python tools/capture_device_snapshot.py

This writes UTF-8/byte-exact copies under ./device_snapshot. It does not
load/unload the LKM, apply rules, reboot, or write to the device.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
DEST = BASE / "device_snapshot"
ADB = os.environ.get("ADB", "adb")
MOD = "/data/adb/modules/susfs_allinone"
UPDATE = "/data/adb/modules_update/susfs_allinone"


def adb_bytes(*args: str) -> bytes:
    proc = subprocess.run([ADB, *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        raise RuntimeError(
            f"adb {' '.join(args)} failed ({proc.returncode}): "
            f"{proc.stderr.decode('utf-8', 'replace').strip()}"
        )
    return proc.stdout


def adb_text(*args: str) -> str:
    return adb_bytes(*args).decode("utf-8", "replace")


def write_bytes(rel: str, data: bytes) -> None:
    path = DEST / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    print(f"wrote {path} ({len(data)} bytes)")


def write_text(rel: str, text: str) -> None:
    write_bytes(rel, text.encode("utf-8"))


def pull(src: str, rel: str) -> None:
    dst = DEST / rel
    if dst.exists():
        shutil.rmtree(dst) if dst.is_dir() else dst.unlink()
    dst.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run([ADB, "pull", src, str(dst)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode("utf-8", "replace").strip())
    print(f"pulled {src} -> {dst}")


def optional_pull(src: str, rel: str) -> None:
    try:
        pull(src, rel)
    except Exception as exc:  # noqa: BLE001
        print(f"WARN: could not pull {src}: {exc}", file=sys.stderr)


def main() -> int:
    DEST.mkdir(parents=True, exist_ok=True)
    state = adb_text("get-state").strip()
    if state != "device":
        print(f"adb state is {state!r}, expected device", file=sys.stderr)
        return 1

    model = adb_text("exec-out", "getprop", "ro.product.model").strip()
    device = adb_text("exec-out", "getprop", "ro.product.device").strip()
    android = adb_text("exec-out", "getprop", "ro.build.version.release").strip()
    hyperos = adb_text("exec-out", "getprop", "ro.mi.os.version.name").strip()
    selinux = adb_text("exec-out", "getenforce").strip()
    boot_completed = adb_text("exec-out", "getprop", "sys.boot_completed").strip()
    kernel = adb_text("exec-out", "uname", "-a").strip()
    write_text(
        "system.txt",
        "\n".join(
            [
                f"model={model}",
                f"device={device}",
                f"android={android}",
                f"hyperos={hyperos}",
                f"kernel={kernel}",
                f"selinux={selinux}",
                f"boot_completed={boot_completed}",
                "",
            ]
        ),
    )

    write_bytes("status.txt", adb_bytes("exec-out", "sh", f"{MOD}/ctl.sh", "status"))
    write_bytes("module.prop", adb_bytes("exec-out", "cat", f"{MOD}/module.prop"))
    write_bytes("pending_module.prop", adb_bytes("exec-out", "cat", f"{UPDATE}/module.prop"))
    write_bytes("proc_susfs_path.txt", adb_bytes("exec-out", "cat", "/proc/susfs_path"))
    write_bytes("webui_index_snapshot.html", adb_bytes("exec-out", "cat", f"{MOD}/webroot/index.html"))
    write_bytes("file_perms.txt", adb_bytes(
        "exec-out", "ls", "-lZ",
        f"{MOD}/common.sh", f"{MOD}/load.sh", f"{MOD}/apply.sh", f"{MOD}/ctl.sh",
        f"{MOD}/action.sh", f"{MOD}/module.prop", f"{MOD}/webroot/index.html",
        f"{MOD}/webroot/app.js", f"{MOD}/webroot/style.css",
    ))

    ksud = adb_bytes("exec-out", "ksud", "module", "list")
    write_bytes("ksud_module_list.json", ksud)
    try:
        json.loads(ksud.decode("utf-8"))
        print("ksud module list: valid JSON")
    except Exception:
        print("WARN: ksud module list is not valid JSON", file=sys.stderr)

    pm = adb_text("exec-out", "pm", "list", "packages")
    managers = [line for line in pm.splitlines() if any(x in line.lower() for x in ("sukisu", "kernelsu", "resukisu"))]
    wild = [line for line in pm.splitlines() if any(x in line.lower() for x in ("wild", "detector"))]
    write_text("pm_managers.txt", "\n".join(managers) + ("\n" if managers else ""))
    write_text("pm_wild.txt", "\n".join(wild) + ("\n" if wild else ""))

    old = adb_text(
        "exec-out", "sh", "-c",
        "for m in susfs4ksu susfs_oneshot; do "
        "if [ -d /data/adb/modules/$m ]; then "
        "if [ -f /data/adb/modules/$m/disable ]; then echo $m=disabled; "
        "else echo $m=enabled; fi; else echo $m=absent; fi; done",
    )
    write_text("old_modules.txt", old)

    for name in ("config.sh", "sus_path.txt", "hide_modules.txt", "sus_mount.txt", "try_umount.txt"):
        pull(f"{MOD}/config/{name}", f"config/{name}")
    pull(f"{MOD}/state/fail_count", "state/fail_count")
    pull(f"{MOD}/load.log", "logs/load.log")
    pull(f"{MOD}/apply.log", "logs/apply.log")

    optional_pull("/data/local/tmp/allinone_cfg_before_zip_install", "backups/config_before_zip_install")
    optional_pull("/data/local/tmp/allinone_cfg_before_reset", "backups/config_before_reset")
    optional_pull("/data/local/tmp/allinone_backup_pre_miui", "backups/pre_miui")

    print(f"device snapshot complete: {DEST}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
