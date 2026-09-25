# kernel-modules

Out-of-tree kernel modules for the RZ/V2H RDK Ubuntu image, matching the `extra/` module set
Renesas ships in the prebuilt kernel `.deb` (`mali_kbase`, `mmngr`, `mmngrbuf`, `uvcs_drv`,
`vspm`, `vspm_if`). These are **not** built as part of the kernel tree itself — `rz-utils`'
`build_kernel.sh modules`/`modules-install` only covers `CONFIG_X=m` in-tree modules.

One self-contained script per module, no shared table to keep in sync:

```
kernel-modules/
├── _lib.sh              # shared fetch/patch/build/install helpers, sourced by every script
├── kernel_modules_all.sh # runs all 7 build_*.sh scripts in dependency order, prints a summary
├── build_mmngr.sh
├── build_mmngrbuf.sh
├── build_vspm.sh
├── build_vspm_if.sh     # depends on vspm being built first
├── build_mali_kbase.sh  # needs a local copy of the proprietary Mali DDK tarball (see below)
├── build_88x2bu.sh      # WiFi: RTL8812BU/8822BU USB dongle, not in the extra/ deb set
├── build_uvcs_drv.sh    # Codec, sourced from the renesas-sst tarball (see below)
└── patches/<name>/      # per-module patch series (series file + .patch files)
```

## Usage

Each script takes the same subcommands as the other `local-build-scripts/build_*.sh` files:

```bash
cd local-build-scripts/kernel-modules
./build_mmngr.sh fetch      # clone/extract source + apply patches
./build_mmngr.sh all        # fetch + build (default if no argument given)
./build_mmngr.sh install    # build + install into KERNEL_MODULES_OUTPUT_DIR, refresh depmod
./build_mmngr.sh clean      # make clean in the module's build dir
```

Prerequisite: the kernel pointed at by `config.ini`'s `KERNEL_DIR` must already be built
(`Module.symvers` present) — external modules link against it:

```bash
cd local-build-scripts
./main_build.sh kernel modules-install
```

`vspm_if` additionally needs `vspm` built first (it links against `vspm`'s `Module.symvers`,
staged as `$KERNEL_DIR/include/vspm.symvers`):

```bash
./build_vspm.sh all
./build_vspm_if.sh all
```

`kernel_modules_all.sh` runs all 7 scripts in that dependency order for you (`fetch`/`all`/
`install`/`clean`, same subcommands), then prints an OK/FAILED summary per module:

```bash
./kernel_modules_all.sh install
```

`mali_kbase` needs the proprietary Mali DDK tarball (`mali-g31_km_v1.3.0.tar.gz`), default
`vendor/mali-g31_km_v1.3.0.tar.gz`; override with `MALI_DDK_TAR=...`.

`uvcs_drv` is sourced from the renesas-sst tarball `uvcs_kernel_package.tar.bz2` (same as the
Yocto recipe), default `vendor/uvcs_kernel_package.tar.bz2`; override with `UVCS_TAR=...`.

## Status

**mmngr, mmngrbuf, vspm, vspm_if, mali_kbase** — build, install, `insmod`-clean on real V2H RDK
hardware. `mali_kbase` probes real HW (`GPU identified as 0x3 arch 7.0.9 r0p0`).

`uvcs_drv` — builds clean, verified via the Yocto recipe (full `core-image-weston` pass,
2026-09-25); not yet re-`insmod`-tested on board with this exact source since dropping the AI
SDK tarball.

`88x2bu` — builds/installs clean; not yet `insmod`-tested (board unreachable), and not confirmed
this V2H RDK actually carries an RTL8812BU dongle.

`mali_kbase` runtime-PM bug (fixed): `power-domains = <&cpg>` on the GPU devicetree node made
genpd double-manage clocks alongside `mali_kbase`'s own handling → `-ESHUTDOWN` (-108) and
`clk_core_disable` warnings on idle/resume. Fixed upstream at the DT level (`meta-rz-graphics`
removed `power-domains` from the GPU node) instead of patching the driver — verified clean under
weston + glmark2 with only patches 0001-0004 (0005/0006 removed, no longer needed).

## Kernel-6.18 API breaks found so far

- **mmngr** (`0016`): `follow_pte()` → `follow_pfnmap_start/end()`; void `.remove`.
- **mmngrbuf** (`0004`): void `.remove`; `MODULE_IMPORT_NS(DMA_BUF)` → quoted-string form.
- **vspm** (`0016`): void `.remove` x3; `EXTRA_CFLAGS` → `ccflags-y`.
- **vspm_if** (`0006`): same two fixes as vspm.
- **mali_kbase**: no patch — build-invocation fix. `build_mali_kbase.sh` now runs the DDK's own
  `Makefile` (not `Kbuild` directly) so `CONFIG_MALI_*` reaches the driver; also needed real stub
  bodies in `mali_kbase_mem_migrate.c` (empty stubs left symbols undefined).
- **88x2bu**: no patch; `build_88x2bu.sh` passes `KSRC`/`KVER` as `make` command-line vars since
  the driver's own Makefile sets them with `:=`.
- **uvcs_drv** (`0005`): void `.remove`; `del_timer()` → `timer_delete()`; `from_timer()` →
  `container_of()`.

## WiFi driver support (Task 08 checklist item)

Checked against `renesas_defconfig`:
- `lwfinger/rtw88` — redundant, already in-tree (`CONFIG_RTW88_8822BU/8723DU/8821CU/8822CU=m`).
- Also in-tree: `CONFIG_MWIFIEX`, `CONFIG_BRCMFMAC`, `CONFIG_IWLWIFI`, `mt76x2`.
- `morrownr/88x2bu` — the one real gap (RTL8812B, not covered by `rtw88`). `build_88x2bu.sh`
  builds clean; only needed if the board's dongle is actually 8812B-based.
