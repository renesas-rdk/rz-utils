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

## Usage

```
Usage: 

$ ./main_build.sh <target_build> <sub_command> 

Option:
    <target_build>:
        1. kernel
            Build for Linux Kernel
            <sub_command>:
                - clean
                - distclean
                - defconfig
                - menuconfig
                - image
                - dtbs
                - all
                - modules
                - modules-install

        2. uboot
            Build for U-Boot
            <sub_command>:
                - clean
                - disclean
                - defconfig
                - image
                - all

        3. atf
            Build for ATF
            <sub_command>:
                - clean
                - distclean
                - bl2
                - bl31
                - all
                - dtbs (not supported yet)

        4. flash-writer
            Build for Flash-Writer
            <sub_command>:
                - clean
                - all

        5. all
            Build for all software stacks (Linux Kernel, U-Boot, ATF, Flash-Writer)
            <sub_command>: None

        6. clean-all
            Clean for all software stacks (Linux Kernel, U-Boot, ATF, Flash-Writer)
            <sub_command>: None

For example: 
    Build all images (Kernel image and device tree) for the Linux Kernel:
        $ ./main-build.sh kernel full-image

    Clean the Linux Kernel (Kernel image and device tree) output:
        $ ./main-build.sh kernel clean

Note: Before executing the build, please make sure that you have updated the configuration file: config.ini at the top of the build scripts folder.
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
