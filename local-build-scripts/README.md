# local-build-scripts

Build scripts for the RZ/V2H RDK (ver1 16GB and ver101 8GB), the only supported board: the
Linux kernel, the out-of-tree kernel modules and the IPL (BL2 + FIP with BL31/U-Boot).

## Hierarchy

```
.
├── main_build.sh        # entry point: kernel, kernel-modules, ipl, deploy, all, clean-all
├── build_kernel.sh      # Linux kernel (KERNEL_DIR)
├── deploy.sh            # built output -> board rootfs layout (DEPLOY_DIR)
├── common.sh            # shared helpers and the main_build.sh usage text
├── config.ini           # build settings, read by every script
├── kernel-config/       # optional kernel config fragments (KERNEL_VARIANT=<name>)
│   └── preempt-rt.config
├── kernel-modules/      # out-of-tree modules: mmngr, mmngrbuf, vspm, vspm_if, mali_kbase,
│                        # uvcs_drv (see kernel-modules/README.md)
└── ipl_build/           # IPL for RDK ver1/ver101 with the Multi-OS options
                         # (see ipl_build/README.md)
```

## Prerequisites

Ubuntu 24.04 host machine or Docker container with Ubuntu 24.04 image.

```bash
sudo apt update
sudo apt install \
    build-essential \
    gcc-aarch64-linux-gnu \
    bc \
    bison \
    flex \
    libssl-dev \
    device-tree-compiler \
    libgnutls28-dev
```

`mali_kbase` and `uvcs_drv` also need proprietary tarballs in `rz-utils/vendor/`, see
[`vendor/README.md`](../vendor/README.md).

## Usage

The scripts can be run from any directory; the examples below run them from this one.
Relative paths (`WORKDIR`, `KERNEL_DIR`, ...) are relative to the directory you run from:

```bash
cd ~/rdk && WORKDIR=ws <path>/rz-utils/local-build-scripts/main_build.sh all    # sources and output in ~/rdk/ws
```

```
$ ./main_build.sh <target_build> [<sub_command>] [<module>]

    kernel <sub_command>
        clean | distclean | reset-src | defconfig | menuconfig | image | dtbs |
        modules | modules-install | all

    kernel-modules <sub_command> [<module>]
        fetch | reset-src | all | install | clean
        Needs the kernel built first. Without <module>, all modules in dependency
        order; <module> is one of mmngr, mmngrbuf, vspm, vspm_if, mali_kbase, uvcs_drv.

    ipl [<sub_command>]
        all (default) | keep | force | clean
        all:   check out TF-A/U-Boot, apply the ipl_build patches and build; stops if
               IPL_WORK_DIR has local changes
        keep:  rebuild IPL_WORK_DIR as it is, with local changes
        force: discard local changes in IPL_WORK_DIR, patch and build again
        clean: remove IPL_OUT_DIR (sources are kept)

    deploy      copy what is built into the board rootfs layout, DEPLOY_DIR/rzv2h-rdk[-rt]
    all         kernel all, kernel-modules install, ipl all, deploy
    clean-all   kernel distclean, kernel-modules clean, ipl clean
```

Examples:

```bash
./main_build.sh kernel all                    # Image, DTBs/overlays, modules + modules-install
./main_build.sh kernel-modules install        # all out-of-tree modules
./main_build.sh kernel-modules all vspm       # one module
./main_build.sh ipl                           # IPL for IPL_BOARDS (default ver101)
IPL_BOARDS="ver1 ver101" IPL_FEATURES=RZ_CM33_COLDBOOT ./main_build.sh ipl
KERNEL_VARIANT=preempt-rt ./main_build.sh kernel all
./main_build.sh deploy                        # boot/ + usr/lib/modules/ for the board
```

`./main_build.sh` without arguments prints the full help. Each script also runs on its own:
`./build_kernel.sh <sub_command>`, `kernel-modules/build_<module>.sh <sub_command>`,
`ipl_build/build_ipl.sh [ver1|ver101]`.

The kernel build targets (`image`, `dtbs`, `modules`, `modules-install`, `all`) run
`defconfig` only when there is no `.config`, or when the defconfig, `KERNEL_VARIANT` or its
fragment changed since the last `defconfig`. Otherwise they build the current `.config`, so
`menuconfig` changes are kept until the next `./main_build.sh kernel defconfig`.

The IPL default mode is remoteproc: set `enable_overlay_remoteproc=1` in `boot/uEnv.txt`
(see `ipl_build/uEnv.txt`), and leave it unset in the other Multi-OS modes.

### deploy

`./main_build.sh deploy` copies what is built into the layout of the board's root filesystem,
without a .deb:

```
DEPLOY_DIR/rzv2h-rdk/                          # rzv2h-rdk-rt/ with KERNEL_VARIANT=preempt-rt
├── boot/Image
├── boot/dtb/renesas/rzv2h-rdk-{ver1,ver101}.dtb
├── boot/dtb/renesas/overlays/rzv2h-rdk-*.dtbo
├── boot/uEnv.txt                              # ipl_build/uEnv.txt
├── boot/{bl2_bp_esd,fip}-rzv2h-rdk-<ver>.bin  # IPL of IPL_BOARDS, for flashing
├── usr/lib/modules/<release>/                 # in-tree + extra/ (out-of-tree), debug-stripped
└── deploy-info.txt                            # flavour, release, sources, date
```

- `KERNEL_VARIANT` selects the flavour, as for the kernel build. The kernel is deployed only if
  its `.config` and `Image` are of that flavour, and the modules only if every `.ko` of
  `lib/modules/<release>` has the matching vermagic (`preempt` / `preempt_rt`), so an RT and a
  non-RT build never end up in the same tree.
- Anything not built (kernel, modules, the IPL of a board) is skipped with a message; the
  command fails only if there is nothing at all to deploy.
- The output directory is recreated on every run. `KBUILD_OUTPUT` is honoured for a kernel
  built out of tree. `DEPLOY_STRIP=0` keeps the module debug info.

Copy it to the board with `rsync -a --exclude deploy-info.txt DEPLOY_DIR/rzv2h-rdk/ root@<board>:/`
and reboot; flash the IPL as in `ipl_build/README.md`.

## config.ini

Review it before a build. Every setting can also be overridden from the environment.

| Setting | Use |
|---|---|
| `WORKDIR` | base directory of the sources and outputs below (default `workspace/` at the top of this repo, ignored by git) |
| `KERNEL_DIR` | Linux kernel source, cloned from `KERNEL_REPO` / `KERNEL_BRANCH` if missing (never pulled or reset afterwards) |
| `KERNEL_SRCREV` | optional: pin the kernel to a commit (checked out with `-f`, local changes are lost) |
| `KERNEL_VARIANT` | optional: merge `kernel-config/<name>.config` on top of `renesas_defconfig`, e.g. `preempt-rt` |
| `EXT_MODULES_SRC_DIR` | sources of the out-of-tree modules |
| `KERNEL_MODULES_OUTPUT_DIR` | install directory of the in-tree and out-of-tree modules |
| `IPL_BOARDS` | IPL boards: `ver1` and/or `ver101` (default `ver101`) |
| `IPL_WORK_DIR` / `IPL_OUT_DIR` | TF-A/U-Boot sources and IPL output |
| `IPL_FEATURES_FILE` / `IPL_FEATURES` | Multi-OS options file, or the options themselves (default `ipl_build/machine-features.conf`) |
| `DEPLOY_DIR` | output of `deploy` (default `$WORKDIR/deploy`) |