#!/bin/bash

source ./config.ini
source ./common.sh

# Overrides common.sh's show_help with one scoped to this script.
show_help() {
	cat <<USAGE
Usage: ./build_uboot.sh [sub_command]

Build U-Boot (${UBOOT_DIR}) for the RZ/V2H RDK board. Called directly or via
'./main_build.sh uboot <sub_command>'.

  <sub_command>:
    clean       make clean
    distclean   make distclean
    reset-src   Reset UBOOT_DIR to UBOOT_SRCREV and reapply UBOOT_PATCHES, without re-cloning
    defconfig   reset-src, then write the UBOOT_VARIANT defconfig (make <defconfig>)
    image       make (build using the existing .config, no defconfig/reset step)
    ver1        Build the 16GB-RAM board variant only
    ver101      Build the 8GB-RAM board variant only
    all         Build both ver1 and ver101 (default if no sub_command given)

UBOOT_VARIANT=<ver1|ver101> (env var, default ver101) selects the defconfig
'defconfig'/'image' use -- 'ver1'/'ver101'/'all' always pick theirs explicitly.
USAGE
	exit 1
}

# Check U-Boot location
if [ -z "${UBOOT_DIR}" ]; then
	echo "UBOOT_DIR is not set properly at config.ini file."
	echo "Please recheck your setup"
	exit 1
fi

if [ -n "${UBOOT_PATCH_DIR:-}" ]; then
	UBOOT_PATCH_DIR="$(cd "${UBOOT_PATCH_DIR}" && pwd)"
fi

# Pin to UBOOT_SRCREV (needed so UBOOT_PATCHES always apply onto the same known base).
if [ -n "${UBOOT_SRCREV:-}" ]; then
	ensure_src_dir_at_rev "${UBOOT_DIR}" "${UBOOT_REPO:-}" "${UBOOT_SRCREV}" "U-Boot"
else
	ensure_src_dir "${UBOOT_DIR}" "${UBOOT_REPO:-}" "${UBOOT_BRANCH:-}" "U-Boot"
fi

# Reset to the pristine pinned commit (undoes any previously applied UBOOT_PATCHES too,
# including untracked files a patch added -- clean_repo() also runs `git clean -fdx`).
reset_uboot_tree() {
	clean_repo "${UBOOT_DIR}" "U-Boot"
}

# config.ini's UBOOT_PATCH_DIR / UBOOT_PATCHES -- board patches not yet upstream.
apply_uboot_patches() {
	if [ -z "${UBOOT_PATCH_DIR:-}" ]; then
		echo "UBOOT_PATCH_DIR is not set in config.ini -- skipping board patches." >&2
		return 0
	fi
	local p
	for p in "${UBOOT_PATCHES[@]}"; do
		if [ ! -f "${UBOOT_PATCH_DIR}/${p}" ]; then
			echo "Error: patch not found: ${UBOOT_PATCH_DIR}/${p}" >&2
			exit 1
		fi
		echo "Applying ${p}..."
		git -C "${UBOOT_DIR}" apply "${UBOOT_PATCH_DIR}/${p}"
	done
}

mk_reset_src() {
	reset_uboot_tree
	apply_uboot_patches
}

# U-Boot has no shared defconfig like the kernel's renesas_defconfig -- it's
# per-board. rzv2h-rdk-ver101_defconfig / rzv2h-rdk-ver1_defconfig were added
# by the UBOOT_PATCHES board-support patches.
defconfig_for_variant() {
	echo "rzv2h-rdk-${1}_defconfig"
}

# Setup the build
uboot_setup() {
	unset LD_LIBRARY_PATH
	unset LDFLAGS CFLAGS CPPFLAGS
}

# Copy the just-built binaries into RELEASE_OUTPUT_DIR/<board-variant>/, read
# from the actual .config (CONFIG_DEFAULT_DEVICE_TREE) rather than the
# variant just requested, so `image` (no defconfig step) still tags correctly
# if .config came from a different variant than the current invocation.
publish_release() {
	local tag outdir
	tag="$(sed -n 's/^CONFIG_DEFAULT_DEVICE_TREE="\(.*\)"$/\1/p' .config)"
	if [ -z "${tag}" ]; then
		echo "Warning: could not read CONFIG_DEFAULT_DEVICE_TREE from .config -- skipping RELEASE_OUTPUT_DIR copy." >&2
		return 0
	fi
	if [ -z "${RELEASE_OUTPUT_DIR:-}" ]; then
		echo "RELEASE_OUTPUT_DIR is not set in config.ini -- skipping release copy." >&2
		return 0
	fi
	outdir="${RELEASE_OUTPUT_DIR}/${tag}"
	mkdir -p "${outdir}"
	cp u-boot.bin "${outdir}/u-boot.bin"
	cp u-boot.srec "${outdir}/u-boot.srec"
	echo "Published u-boot.bin/.srec to ${outdir}/"
}

mk_image() {
	uboot_setup
	make -j"$(nproc)"
	publish_release
}

mk_clean() {
	make clean
}

mk_distclean() {
	make distclean
}

mk_defconfig() {
	local variant="${UBOOT_VARIANT:-ver101}"
	mk_reset_src
	uboot_setup
	make "$(defconfig_for_variant "${variant}")"
}

# Full build for one board variant: reset+patch, defconfig, build, publish.
build_variant() {
	local variant="$1"
	echo "===== Building U-Boot for the ${variant} RAM variant ====="
	mk_reset_src
	uboot_setup
	make "$(defconfig_for_variant "${variant}")"
	make -j"$(nproc)"
	publish_release
}

# Main U-Boot build
echo "Starting the U-Boot build ${1} at ${UBOOT_DIR}"
cd "${UBOOT_DIR}" || exit 1

case ${1} in
	'clean')
		mk_clean
		;;
	'distclean')
		mk_distclean
		;;
	'reset-src')
		mk_reset_src
		;;
	'defconfig')
		mk_defconfig
		;;
	'image')
		mk_image
		;;
	'ver1')
		build_variant "ver1"
		;;
	'ver101')
		build_variant "ver101"
		;;
	'all')
		build_variant "ver1"
		build_variant "ver101"
		;;
	*)
		show_help
		;;
esac

exit 0
