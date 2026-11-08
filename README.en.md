# LKM SUSFS Manager

<p align="center">
  <b>KernelSU family · Magisk · APatch (experimental)</b><br>
  <b>SUSFS LKM auto-match / load / rule manager</b><br>
  <sub><a href="README.md">中文</a> · English</sub>
</p>

<p align="center">
  <img alt="License" src="https://img.shields.io/badge/license-GPL--2.0-blue.svg">
  <img alt="Component" src="https://img.shields.io/badge/component-AGPL--3.0-orange.svg">
  <img alt="Arch" src="https://img.shields.io/badge/arch-arm64-lightgrey.svg">
  <img alt="KMI" src="https://img.shields.io/badge/KMI-8%20targets-green.svg">
  <img alt="Managers" src="https://img.shields.io/badge/managers-KernelSU%20%7C%20Magisk%20%7C%20APatch-blueviolet.svg">
  <img alt="Release" src="https://img.shields.io/github/v/release/DawnyFY/lkm-susfs-manager?color=brightgreen">
</p>

---

A **multi-manager** SUSFS LKM module: auto-detect KMI → load the SUSFS LKM → apply rules → write status back to the module description. Includes a MIUIX-style WebUI (Chinese/English).

It is no longer limited to the KernelSU family:

- **KernelSU family**: official KernelSU / SukiSU / ReSukiSU / BakaSU / KernelSU Next
- **Magisk**: rules are applied in the late_start stage
- **APatch / KernelPatch**: experimental; the LKM is not loaded by default and must be explicitly allowed

> **Experimental project.** KSU family has real-device cold/hot boot validation; Magisk has code-level support only; APatch has QEMU validation only and is **not verified on a real device**. Flashing and rooting are risky; keep a recovery path.

## Compatibility

| Manager | Support | Validation | Boot stages |
|---|---|---|---|
| KernelSU official / SukiSU / ReSukiSU / BakaSU / KernelSU Next | Full | SukiSU cold/hot boot tested; others code-compatible, not device-tested individually | post-fs-data → boot-completed |
| Magisk | Full | Code-level support; no real-device cold boot test | post-fs-data → service |
| APatch / KernelPatch | **Experimental** | QEMU GKI only; no real-device acceptance | post-fs-data → boot-completed, LKM denied by default |

## Quick start

1. Download `susfs_allinone-<version>.zip` from [Releases](https://github.com/DawnyFY/lkm-susfs-manager/releases).
2. Install with your manager:
   - **KernelSU family**: Modules → Install from local storage.
   - **Magisk**: Modules → Install from local storage.
   - **APatch**: install the zip using an APatch-compatible module method (APatch Manager install flow is not yet device-verified). The LKM stays disabled by default.
3. Reboot, or run the module Action to load manually.
4. Open the WebUI to inspect status and rules.

Upgrade by flashing the new zip over the old one; `config/` and `state/` are preserved.

## Features

- **8 KMI targets** (android12-5.10 through android17-6.18). Shared 5.15 kernels without an Android tag use SDK-based disambiguation where possible.
- **Manager-aware boot stages**: KSU family / APatch use `boot-completed`; Magisk uses `service`. Late-load temporary-root setups get a fallback.
- **APatch / KernelPatch detection**: recognizes `/data/adb/ap` / `apd`; disables overlapping `avc_spoof`; denies LKM loading by default.
- **KernelPatch runtime probe**: reads the `KernelPatch Version:` dmesg banner; reports `unknown` when dmesg is unavailable instead of guessing.
- **Boot guard / pstore crash pause / half-load protection**: avoids bootloops after a bad LKM.
- **Rules and hiding**: `sus_path`, `sus_mount`, `try_umount`, `hide_modules`, AVC spoofing, optional extra hiding.
- **WebUI**: status / config / logs / about; APatch environments get an extra APatch card.

## APatch (experimental)

Under APatch/KernelPatch the SUSFS LKM is **not auto-loaded** and manual loading is denied. If your kernel has no built-in SUSFS and you accept the risk:

```sh
su -c "sh /data/adb/modules/susfs_allinone/ctl.sh allow_lkm"
```

Or use the APatch card in the WebUI. A QEMU module-level path has passed 14/14 assertions, but real-device install, ABI, and WebUI interaction are not verified.

Read [APatch experimental support](docs/APATCH.md) (Chinese) before enabling it.

## Safety

- Do not load the LKM twice; do not enable two SUSFS LKM modules at the same time.
- Do not run `rmmod susfs_guard_lkm`; disable the module and reboot instead.
- APatch opt-in may cause a bootloop; test devices only.
- Keep `load.log` and `apply.log` when reporting issues.

Full safety and disclaimer: [SAFETY.md](docs/SAFETY.md) (Chinese).

## Verification and limitations

- KSU family: 1.2.3 cold boot loads the LKM, rules and integrity are OK; hot reboot keeps the module healthy and restores LSPosed.
- QEMU GKI: LKM load/hide/restore; module-level APatch path 14/14.
- Offline: 29/29 tests pass.
- Not verified: Magisk real-device cold boot, APatch real-device full chain, the other 7 KMI targets.
- Known gap: `sus_path` rules on deleted/recreated inodes stop hiding; the reattach prototype is not merged.
- Default hiding of `/data/adb`: NeoZygisk users should remove that line or exclude `/data/adb/neozygisk` (externally reported zygote loop risk).

See [VERIFICATION.md](docs/VERIFICATION.md) (Chinese).

## Documentation

Detailed documentation is currently in Chinese. The English README covers the quick start; the following pages contain the full details.

| Document | Content |
|---|---|
| [INSTALL.md](docs/INSTALL.md) | KSU / Magisk / APatch install, upgrade, rollback |
| [APATCH.md](docs/APATCH.md) | APatch verified/unverified scope, opt-in, risks |
| [KMI.md](docs/KMI.md) | KMI table, dirty kernels, force KMI, diagnostics |
| [CONFIG.md](docs/CONFIG.md) | config.ini, rule files, WebUI |
| [FAQ.md](docs/FAQ.md) | load failures, APatch card, Magisk, Zygisk |
| [VERIFICATION.md](docs/VERIFICATION.md) | device/QEMU/offline results, limitations |
| [SAFETY.md](docs/SAFETY.md) | safety rules and disclaimer |
| [UPSTREAM.md](docs/UPSTREAM.md) | upstream components, versions, licenses, credits |
| [SUPPORT.md](docs/SUPPORT.md) | feedback channels and required information |

## Feedback

- Bugs: [open an issue](https://github.com/DawnyFY/lkm-susfs-manager/issues/new?template=bug_report.yml)
- Feature requests: [feature request](https://github.com/DawnyFY/lkm-susfs-manager/issues/new?template=feature_request.yml)
- Usage / configs: [Discussions](https://github.com/DawnyFY/lkm-susfs-manager/discussions)
- Security: see `SECURITY.md`; do not open a public issue
- Upstream `.ko` / `ksu_susfs` issues: report to the upstream projects

Please include `load.log`, `apply.log` and `ctl.sh status`. For APatch, also include the KernelPatch version and `allow_lkm` state.

## License

- Scripts/installer/WebUI: **GPL-2.0** (`LICENSE`)
- Third-party binaries: `lib/susfs_guard_lkm-*.ko`, `bin/susfs_insmod` (GPL-2.0), `bin/ksu_susfs_good` (AGPL-3.0)
- Copyright and licenses remain with the original authors; see [UPSTREAM.md](docs/UPSTREAM.md), `NOTICE` and `provenance.json`

---

**If you do not fully understand the risks, do not install this module.**
