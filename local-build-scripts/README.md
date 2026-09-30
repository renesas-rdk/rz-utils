# local-build-scripts

This directory contains build scripts for all software stacks of the RZ Board Support Package (BSP).

## Hierarchy

```
.
├── kernel-modules
├── ATF_patches
├── build_atf.sh
├── build_firmware_pack.sh
├── build_flash_writer.sh
├── build_kernel.sh
├── build_uboot.sh
├── common.sh
├── config.ini
├── main_build.sh
└── README.md

1 directory, 9 files
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

This configuration file contains the configurations for the build. Please make sure that you review all the settings carefully before performing a build.
```bash
- **KERNEL_DIR**: Address the Linux Kernel source code location.
- **KERNEL_MODULES_OUTPUT_DIR**: Address the output directory for the Linux Kernel modules.
- **UBOOT_DIR**: Address the U-Boot source code location.
- **ATF_DIR**: Address the ATF source code location.
- **FLASH_WRITER_DIR**: Address the Flash-Writer source code location.
```


## Usage

```
# Build all componets:
$ ./main_build.sh all
	Build for all (Linux Kernel, U-Boot, ATF, Firmware-Pack, Flash-Writer, kernel modules)

$ ./main_build.sh clean
	Clean for all (Linux Kernel, U-Boot, ATF, Firmware-Pack, Flash-Writer, kernel modules)


# Build only 1 component:
# Kernel:
$ ./build_kernel.sh clean            # make clean
$ ./build_kernel.sh all              # everything (same as modules-install)

# U-Boot:
$ ./build_uboot.sh clean       # make clean
$ ./build_uboot.sh all         # defconfig + full image build

# ATF:
$ ./build_atf.sh clean       # reset the ATF tree, then make clean
$ ./build_atf.sh 8gb         # build the 8GB-RAM board variant
$ ./build_atf.sh 16gb        # build the 16GB-RAM board variant
$ ./build_atf.sh all         # same as 16gb

# Flash-writer:
$ ./build_flash_writer.sh clean   # make clean
$ ./build_flash_writer.sh all     # build the flash-writer image

# Firmware-pack:
$ ./build_firmware_pack.sh bptool   # build the bptool host tool only
$ ./build_firmware_pack.sh all      # bptool, then package ATF's BL2/FIP (needs U-Boot built first)

# Kernel modules (out-of-tree, see kernel-modules/README.md):
$ ./build_<name>.sh all     # (re-)fetch source + re-apply every patch + build + install
$ ./build_<name>.sh clean   # make clean in the module's build dir

$ ./kernel-modules/kernel_modules_all.sh all    # runs all 7 build_<name>.sh all in dependency order
$ ./kernel-modules/kernel_modules_all.sh clean  # same, for clean
```
