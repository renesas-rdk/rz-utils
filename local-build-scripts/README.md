# local-build-scripts

This directory contains build scripts for all software stacks of the RZ Board Support Package (BSP).

## Hierarchy

```
.
├── kernel-modules
├── ATF_patches
│   ├── rz-v2h-rdk-ver1       # 16GB-RAM board variant patches
│   └── rz-v2h-rdk-ver101     # 8GB-RAM board variant patches
├── u-boot_patches
├── build_atf.sh
├── build_firmware_pack.sh
├── build_flash_writer.sh
├── build_kernel.sh
├── build_uboot.sh
├── common.sh
├── config.ini
├── main_build.sh
└── README.md
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
    libgnutls28-dev \
    srecord
```

### config.ini

This configuration file contains the configurations for the build -- it is the
single source of truth for what gets built: source repo/branch/pinned commit,
which patches apply, and where output lands. Please review all the settings
carefully before performing a build.

```bash
- **KERNEL** 
- **KERNEL_MODULES**
- **ATF**
- **FLASH_WRITER**
- **BPTOOL**
- **FIRMWARE_PACK_OUTPUT**
```
## Output layout

After building both variants, `RELEASE_OUTPUT_DIR` (`$WORKDIR/release` by
default) looks like:

```
release/
├── rzv2h-rdk-ver1/        # 16GB-RAM board
│   ├── u-boot.bin / .srec
│   ├── bl2.bin
│   ├── bl2_bp_{spi,mmc,esd}.bin / .srec
│   └── fip.bin / .srec
└── rzv2h-rdk-ver101/      # 8GB-RAM board
    └── (same set)
```

## Usage
```bash
# Build everything by main_build.sh:
# -- Flash-Writer 
# -- ATF
# -- U-Boot
# -- Firmware-Pack
# -- Kernel + kernel modules
$ ./main_build.sh all
$ ./main_build.sh clean

# Kernel:
$ ./build_kernel.sh clean
$ ./build_kernel.sh reset-src         # reset to KERNEL_SRCREV, no build
$ ./build_kernel.sh all               # defconfig + Image + dtbs + modules + modules-install
	Builds rzv2h-rdk-ver1.dtb and rzv2h-rdk-ver101.dtb together (one kernel
	Image serves both boards; only U-Boot needs a separate build per variant).

# U-Boot
$ ./build_uboot.sh clean
$ ./build_uboot.sh reset-src          # reset UBOOT_DIR + reapply UBOOT_PATCHES only, no build
$ ./build_uboot.sh all                # defconfig (ver101) + full image build, publishes to RELEASE_OUTPUT_DIR
$ ./build_uboot.sh image              # rebuild with the existing .config, no defconfig/reset step

# ver1 (16GB) U-Boot -- manual until wired into build_uboot.sh's PLATFORM case:
$ cd /workspace/workspace/u-boot
$ export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
$ make rzv2h-rdk-ver1_defconfig && make -j$(nproc)
$ cd - && ./build_uboot.sh image      # publishes it to RELEASE_OUTPUT_DIR/rzv2h-rdk-ver1/
	(publish_release() reads CONFIG_DEFAULT_DEVICE_TREE from .config, so this
	tags it correctly regardless of PLATFORM.)

# ATF -- each variant can pin its own TF-A commit and patch set (config.ini's
# ATF_SRCREV_<VARIANT> / ATF_PATCHES_<VARIANT>):
$ ./build_atf.sh clean
$ ./build_atf.sh ver1          # 16GB-RAM board variant
$ ./build_atf.sh ver101        # 8GB-RAM board variant
$ ./build_atf.sh all           # both, publishes bl2.bin to RELEASE_OUTPUT_DIR

# Flash-writer:
$ ./build_flash_writer.sh clean
$ ./build_flash_writer.sh all

# Firmware-pack -- needs U-Boot already built
$ ./build_firmware_pack.sh bptool    # build the bptool host tool only
$ ./build_firmware_pack.sh ver1
$ ./build_firmware_pack.sh ver101
$ ./build_firmware_pack.sh all       # bptool, then package both variants

# Kernel modules (out-of-tree, see kernel-modules/README.md):
$ ./build_<name>.sh all     # (re-)fetch source + re-apply every patch + build + install
$ ./build_<name>.sh clean   # make clean in the module's build dir

$ ./kernel-modules/kernel_modules_all.sh all    # runs all 7 build_<name>.sh all in dependency order
$ ./kernel-modules/kernel_modules_all.sh clean  # same, for clean
```

## Realtime preempt:
```bash
# Build kernel-rt:
$ KERNEL_VARIANT=preempt-rt \
$ KERNEL_MODULES_OUTPUT_DIR=/workspace/workspace/kernel-modules-rt \
$ ./build_kernel.sh all

# Build kernel modules-rt
$ cd kernel-modules
$ KERNEL_MODULES_OUTPUT_DIR=/workspace/workspace/kernel-modules-rt ./kernel_modules_all.sh all
```
