#!/bin/bash

# main_build.sh sets these too (with extra hardening CFLAGS on top), but each
# build_<target>.sh is also meant to be runnable standalone -- default them
# here so a direct invocation still cross-compiles instead of silently
# falling back to the host gcc/as/ld and failing on target-specific flags
# (e.g. -march=armv8-a+crc, -mstrict-align).
export ARCH="${ARCH:-arm64}"
export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"

# Each build_<target>.sh calls this before building, so a missing source
# checkout fails fast with a clear message instead of deep inside `make`.
#
#   ensure_src_dir <dir> <repo> <branch> <label>
#
# - <dir> already exists and is a git repo (has .git)   -> left alone, no-op.
#   This never pulls/resets an existing checkout -- it may hold local
#   patches or be intentionally on a different branch than <branch>.
# - <dir> does not exist                                -> git clone -b
#   <branch> <repo> <dir>, using <repo>/<branch> from config.ini.
# - <dir> exists but is NOT a git repo (e.g. empty)      -> error, stop.
#   Refuses to clone into or delete a directory that might hold data we
#   don't understand.
ensure_src_dir() {
	local dir="$1" repo="$2" branch="$3" label="$4"

	if [ -d "${dir}/.git" ]; then
		return 0
	fi

	if [ -e "${dir}" ]; then
		echo "Error: ${dir} exists but is not a git repository (no .git found)." >&2
		echo "Refusing to auto-clone ${label} into it -- please check/remove this directory manually." >&2
		exit 1
	fi

	if [ -z "${repo}" ] || [ -z "${branch}" ]; then
		echo "There is no ${label} source at ${dir}, and no repo/branch configured in config.ini to clone it automatically." >&2
		echo "Please clone it manually, or set the matching *_REPO/*_BRANCH variables in config.ini." >&2
		exit 1
	fi

	echo "${label} source not found at ${dir}, cloning ${repo} (branch ${branch})..."
	git clone --branch "${branch}" "${repo}" "${dir}"
}

# Like ensure_src_dir(), but pins to a fixed commit instead of a branch tip --
# for tools whose source is only ever meant to be built at one exact
# upstream revision (e.g. bptool, from a different repo than ATF_REPO).
# Unlike ensure_src_dir(), this DOES re-sync an existing checkout when it is
# sitting on the wrong commit -- there is no "local dev work" to preserve for
# a pinned build tool.
#
#   ensure_src_dir_at_rev <dir> <repo> <rev> <label>
ensure_src_dir_at_rev() {
	local dir="$1" repo="$2" rev="$3" label="$4"
	local have

	if [ -z "${repo}" ] || [ -z "${rev}" ]; then
		echo "There is no ${label} source at ${dir}, and no repo/rev configured in config.ini to clone it automatically." >&2
		echo "Please clone it manually, or set the matching *_REPO/*_SRCREV variables in config.ini." >&2
		exit 1
	fi

	if [ ! -d "${dir}/.git" ]; then
		if [ -e "${dir}" ]; then
			echo "Error: ${dir} exists but is not a git repository (no .git found)." >&2
			echo "Refusing to auto-clone ${label} into it -- please check/remove this directory manually." >&2
			exit 1
		fi
		echo "${label} source not found at ${dir}, cloning ${repo}..."
		git clone -q "${repo}" "${dir}"
	fi

	have="$(git -C "${dir}" rev-parse HEAD 2>/dev/null)"
	if [ "${have}" = "${rev}" ]; then
		echo "${label}: already at ${rev}"
		return 0
	fi

	if ! git -C "${dir}" cat-file -e "${rev}^{commit}" 2>/dev/null; then
		git -C "${dir}" fetch -q --all --tags
	fi
	echo "${label}: checking out ${rev}"
	git -C "${dir}" checkout -q -f "${rev}"
}

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

        6. firmware-pack
            Package ATF's BL2/FIP into the boot-header + S-record form the board's
            SCIF/Flash-Writer boot flow expects. Needs U-Boot already built (uboot all)
            -- BL33=${UBOOT_DIR}/u-boot.bin is required for ATF's fip target.
            <sub_command>:
                - bptool (build the bptool host tool only)
                - all

        7. build-all
            Build for all software stacks (Linux Kernel, U-Boot, ATF, Firmware-Pack,
            Flash-Writer)
            <sub_command>: None

        8. clean-all
            Clean for all software stacks (Linux Kernel, U-Boot, ATF, Firmware-Pack,
            Flash-Writer)
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
