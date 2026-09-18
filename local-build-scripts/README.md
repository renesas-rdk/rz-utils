# local-build-scripts

This directory contains build scripts for all software stacks of the RZ Board Support Package (BSP).

## Hierarchy

```
.
├── build_atf.sh
├── build_flash_writer.sh
├── build_kernel.sh
├── build_uboot.sh
├── common.sh
├── config.ini
├── main_build.sh
└── README.md

1 directory, 8 files
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

- `device-tree-compiler` (`dtc`): needed by both U-Boot and ATF (`build_uboot.sh`,
  `build_atf.sh`) to compile the `.dts` sources into `.dtb` files. The kernel build
  does not need this package -- it vendors and builds its own `scripts/dtc/dtc`.
- `libgnutls28-dev`: needed by U-Boot's host-side `tools/mkeficapsule` (EFI capsule
  update image generator), built as part of `make tools` even though this board's
  boot flow does not use EFI capsule updates.
- `srecord` (provides `srec_cat`): without it, U-Boot's build prints
  `srec_cat: not found` and `expr: syntax error: unexpected argument '1.60'` partway
  through (a version-check `$(shell ...)` call in the Makefile gets an empty result
  and confuses the following `expr`). Cosmetic, not fatal -- the build still
  completes and `u-boot.bin`/`u-boot.elf` are unaffected -- but installing this
  package silences it.

If a source directory (`KERNEL_DIR`, `UBOOT_DIR`, `ATF_DIR`, `FLASH_WRITER_DIR`)
does not exist yet, the matching `build_<target>.sh` clones it automatically
over SSH using the `*_REPO`/`*_BRANCH` values in `config.ini` (see below) --
this needs a GitHub-authorized SSH key available to whichever user runs the
script. In a Docker container this key is *not* inherited from the host
automatically; either bind-mount the host's `~/.ssh` into the container, or
copy `id_rsa`/`id_rsa.pub` in manually, matching the user the build actually
runs as inside the container (e.g. `root` for a plain `docker exec <container>
...` with no `-u`).

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

        5. build-all
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

- **PLATFORM**: Select the supported platform.
- **KERNEL_DIR**: Address the Linux Kernel source code location.
- **KERNEL_MODULES_OUTPUT_DIR**: Address the output directory for the Linux Kernel modules.
- **UBOOT_DIR**: Address the U-Boot source code location.
- **ATF_DIR**: Address the ATF source code location.
- **FLASH_WRITER_DIR**: Address the Flash-Writer source code location.
- **ATF_MODE**: Select the mode for ATF images.
- **KERNEL_REPO/KERNEL_BRANCH, UBOOT_REPO/UBOOT_BRANCH, ATF_REPO/ATF_BRANCH,
  FLASH_WRITER_REPO/FLASH_WRITER_BRANCH**: used only to auto-clone the matching
  `*_DIR` above if it does not already exist -- each `build_<target>.sh` checks
  this at startup (`ensure_src_dir()` in `common.sh`) before building. An
  existing checkout at `*_DIR` is always left alone, whatever branch it is on;
  a directory that exists but is not a git repo (e.g. empty) is treated as an
  error rather than auto-cloned into. `KERNEL_BRANCH` in particular is often
  overridden per task (e.g. switching between the std and RT porting
  branches) -- update it to match whichever branch you actually want cloned.
  Cloning is done with the invoking user's own git/SSH credentials, so it
  only works where those already have access to the repos (see the Docker
  note below for the `son_ubuntu_24`-style container setup).