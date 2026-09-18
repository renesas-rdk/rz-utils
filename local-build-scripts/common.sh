#!/bin/bash

# main_build.sh sets these too (with extra hardening CFLAGS on top), but each
# build_<target>.sh is also meant to be runnable standalone -- default them
# here so a direct invocation still cross-compiles instead of silently
# falling back to the host gcc/as/ld and failing on target-specific flags
# (e.g. -march=armv8-a+crc, -mstrict-align).
export ARCH="${ARCH:-arm64}"
export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"

_usage="
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
                - dtbs

        4. flash-writer
            Build for Flash-Writer
            <sub_command>:
                - clean
                - all

        5. kernel-modules
            Out-of-tree kernel modules (mali_kbase, mmngr, mmngrbuf, vspm, vspm_if -- the
            extra/ set Renesas ships in the prebuilt kernel .deb, not covered by
            kernel modules / kernel modules-install). No aggregator here: each module
            has its own standalone script under kernel-modules/, run directly, e.g.
                cd kernel-modules && ./build_mmngr.sh all
            See kernel-modules/README.md for the full list and build order (vspm_if needs
            vspm built first).

        6. build-all
            Build for all software stacks (Linux Kernel, U-Boot, ATF, Flash-Writer)
            <sub_command>: None

        7. clean-all
            Clean for all software stacks (Linux Kernel, U-Boot, ATF, Flash-Writer)
            <sub_command>: None

For example: 
    Build all images (Kernel image and device tree) for the Linux Kernel:
        $ ./main_build.sh kernel all

    Clean the Linux Kernel (Kernel image and device tree) output:
        $ ./main_build.sh kernel clean

    Build and install kernel modules to KERNEL_MODULES_OUTPUT_DIR:
        $ ./main_build.sh kernel modules-install

Note: Before executing the build, please make sure that you have updated the configuration file: config.ini at the top of the build scripts folder.
      Kernel modules install output path is configured by KERNEL_MODULES_OUTPUT_DIR in config.ini.

Platform Override:
    By default, PLATFORM is read from config.ini, but you can override it at runtime, for example:
        $ PLAT=RZ-CMN ./main_build.sh kernel full-image
"
# Help message
show_help() {
        echo 'Error: Invalid Syntax!'
        echo "${_usage}"
        exit 1
}
