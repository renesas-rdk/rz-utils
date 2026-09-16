# kernel-modules

Out-of-tree kernel modules for the RZ/V2H RDK Ubuntu image, matching the `extra/` module set
Renesas ships in the prebuilt kernel `.deb` (`mali_kbase`, `mmngr`, `mmngrbuf`, `uvcs_drv`,
`vspm`, `vspm_if`). These are **not** built as part of the kernel tree itself — `rz-utils`'
`build_kernel.sh modules`/`modules-install` only covers `CONFIG_X=m` in-tree modules.

One self-contained script per module, no shared table to keep in sync:

```
kernel-modules/
├── _lib.sh              # shared fetch/patch/build/install helpers, sourced by every script
├── build_mmngr.sh
├── build_mmngrbuf.sh
├── build_vspm.sh
├── build_vspm_if.sh     # depends on vspm being built first
├── build_mali_kbase.sh  # needs a local copy of the proprietary Mali DDK tarball (see below)
├── build_88x2bu.sh      # WiFi: RTL8812BU/8822BU USB dongle, not in the extra/ deb set
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

`mali_kbase` needs a local copy of the proprietary Renesas Mali DDK tarball
(`mali-g31_km_v1.3.0.tar.gz`) — the script defaults to `vendor/mali-g31_km_v1.3.0.tar.gz`
alongside this checkout (i.e. `ubuntu_24/vendor/`, so it resolves both on the bare lab157 host
and inside a container that only bind-mounts the `ubuntu_24` tree); override with
`MALI_DDK_TAR=/path/to/tarball.tar.gz ./build_mali_kbase.sh all` elsewhere.

`uvcs_drv` is not yet scripted — its tarball's location has not been confirmed on lab157.

## Status

**All five scripted modules build, install, and are confirmed `insmod`-clean on real V2H RDK
hardware** (over the board's serial console, kernel `6.18.20-yocto-standard+`):

- `mmngr` — bound its device-tree reserved-memory node correctly.
- `mmngrbuf`, `vspm`, `vspm_if` — `vspm_if` shows the correct dependency on `vspm` in `lsmod`.
- `mali_kbase` — probed real hardware: `mali 14850000.gpu: GPU identified as 0x3 arch 7.0.9 r0p0`,
  `Probed as mali0`.

`uvcs_drv` is not yet scripted (see above) — the only module in the `extra/` set left to do.

`88x2bu` (`build_88x2bu.sh`) built clean (no kernel-6.18 patch needed) against a `git worktree` of
`ubuntu/rz-v2h-rdk-rebase-6.18.20` and installs correctly, but is **not yet `insmod`-tested on real
hardware** — the board was unreachable this session — and it is not yet confirmed the V2H RDK
actually carries an RTL8812BU dongle (the only chip mainline `rtw88` does not already cover; see
below).

## Kernel-6.18 API breaks found so far

Patches carried from the kernel-6.10-era `rz-utils-ext-modules` prototype (see
`Task/05_Ubuntu_V4H_RDK_investigate/03_work/rz-utils-ext-modules/` in the notes repo) were not
guaranteed to still compile against 6.18.20, and in practice every module needed a follow-up fix:

- **mmngr** (`patches/mmngr/0016-kernel-6.18-follow_pfnmap-and-void-remove.patch`):
  `follow_pte()` was removed, replaced by `follow_pfnmap_start()`/`follow_pfnmap_end()` (a
  `struct follow_pfnmap_args`); `platform_driver.remove` must return `void`, not `int`.
- **mmngrbuf** (`patches/mmngrbuf/0004-kernel-6.18-void-remove-and-module-import-ns.patch`):
  same void-`.remove` change, plus `MODULE_IMPORT_NS(DMA_BUF)` must now be
  `MODULE_IMPORT_NS("DMA_BUF")` (the macro switched to taking a quoted string).
- **vspm** (`patches/vspm/0016-kernel-6.18-ccflags-and-void-remove.patch`): void-`.remove` for
  all three remove functions (`vspm_vsp_remove`, `vspm_fdp_remove`, `vspm_isu_remove`), plus the
  Makefile's `EXTRA_CFLAGS +=` (long deprecated, silently ignored by modern Kbuild) rewritten to
  `ccflags-y +=`.
- **vspm_if** (`patches/vspm_if/0006-kernel-6.18-ccflags-and-void-remove.patch`): same two
  classes of fix as vspm (void-`.remove`, `EXTRA_CFLAGS` -> `ccflags-y`).
- **mali_kbase** — not a source patch, a **build-invocation** fix (no `patches/mali_kbase/0005-*`
  needed): the DDK's own top-level `Makefile` translates `CONFIG_MALI_*` into real `-D` flags
  (via `KCPPFLAGS`) before invoking the kernel's `Kbuild`, but `build_mali_kbase.sh` used to drive
  `Kbuild` directly (`make -C $KERNEL_DIR M=...`), skipping that translation entirely — so every
  `#if IS_ENABLED(CONFIG_MALI_...)` in the driver evaluated as unset regardless of what was passed
  on the command line. That's what silently routed `device/backend/mali_kbase_device_jm.c`'s
  `dev_init[]` table to the (correctly excluded) dummy hardware-model backend instead of the real
  one, producing ~12 `Unknown symbol` errors at `insmod` — invisible at build time because
  `KBUILD_MODPOST_WARN=1` downgrades the unresolved-symbol *link* error to a warning. Fixed by
  building via the DDK's own `Makefile` (`cd` into the module dir, plain `make`) instead of
  driving `Kbuild` directly — the same fix class as vspm/vspm_if's `EXTRA_CFLAGS`, just one layer
  further up. Also needed real (non-empty) stub bodies for `mali_kbase_mem_migrate.c`'s five
  functions — `kbase_is_page_migration_enabled()` returning `false` is what actually disables
  page migration (kernel 6.18 changed `address_space_operations` completely); the original Task 06
  approach emptied the whole file, which left those five symbols undefined too, for the same
  "warning, not a real fix" reason as above. `hrtimer_init`'s changed signature (from
  meta-rz-graphics' own patch) was the one genuinely correct fix carried over unchanged.
- **88x2bu** — no source patch needed (the `morrownr` fork is actively maintained and already
  claims kernel 7.1.x support), but its own `Makefile` sets `KSRC`/`KVER` with `:=` (unconditional
  assignment), so plain exported env vars cannot override them the way `mmngr`'s `KERNELSRC` env
  vars do — `build_88x2bu.sh` passes `KSRC=$KERNEL_DIR KVER=$(kernel_release)` as `make`
  command-line variables instead, which always win over a makefile's own `:=`/`?=` assignment
  regardless of how it was set internally.

## WiFi driver support (Task 08 checklist item)

Task 08's requirement listed two out-of-tree WiFi sources
(`https://github.com/lwfinger/rtw88.git`, `https://github.com/morrownr/88x2bu-20210702.git`).
Checked against this kernel's own `renesas_defconfig`/`.config` (`ubuntu/rz-v2h-rdk-rebase-6.18.20`):

- **`lwfinger/rtw88` is redundant** — that driver has been upstream in mainline Linux for years;
  this kernel already ships it in-tree and enabled as modules: `CONFIG_RTW88_8822BU=m`,
  `CONFIG_RTW88_8723DU=m`, `CONFIG_RTW88_8821CU=m`, `CONFIG_RTW88_8822CU=m`. No script needed.
- Also already in-tree and enabled: `CONFIG_MWIFIEX` (onboard SDIO), `CONFIG_BRCMFMAC` (PCIe M.2
  Key-E, CYW55573, with its own secure-boot TRX firmware patch already merged), `CONFIG_IWLWIFI`
  (Intel AX210, M.2), `mt76x2` (USB, added by an earlier `renesas_defconfig` commit).
- **`morrownr/88x2bu` is the one genuine gap**: it covers the RTL8812B chip family, which mainline
  `rtw88` does **not** support (only 8822B/8723D/8821C). `build_88x2bu.sh` (pinned at
  `d31ffa827bb95b8a436c2a469b5163b634ac4333`, 2026-09-11) builds clean with no patch required.
  Whether this is actually needed depends on which WiFi module/dongle is physically populated on a
  given V2H RDK board — if it's the M.2 Key-E CYW55573, AX210, or an 8822BU-family USB dongle, the
  in-tree drivers above are already sufficient and this script is not required at all.
