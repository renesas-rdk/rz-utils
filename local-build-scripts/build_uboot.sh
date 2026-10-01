#!/bin/bash

source ./config.ini
source ./common.sh

# Overrides common.sh's show_help with one scoped to this script.
show_help() {
	cat <<USAGE
Usage: ./build_uboot.sh [sub_command]

Build U-Boot (${UBOOT_DIR}). Called directly or via
'./main_build.sh uboot <sub_command>'.

  <sub_command>:
    clean       make clean
    distclean   make distclean
    reset-src   Reset UBOOT_DIR to UBOOT_SRCREV and reapply UBOOT_PATCHES, without re-cloning
    defconfig   reset-src, then write config.ini's DEFCONFIG (make <defconfig>)
    image       make (build using the existing .config, no defconfig/reset step)
    all         defconfig, then make (default if no sub_command given)

Platform override: PLAT=RZV2H-RDK ./build_uboot.sh all
  (defaults to config.ini's PLATFORM, which selects the DEFCONFIG -- see the
  UBOOT_DEFCONFIG case in this script)
USAGE
	exit 1
}

# if PLATFORM is already exported from main_build.sh, keep it
if [ -n "${PLATFORM:-}" ] && [ -n "${PLAT:-}" ]; then
	PLATFORM="$PLAT"
fi

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

# Reset to the pinned commit
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

# Setup the build
uboot_setup() {
	unset LD_LIBRARY_PATH
	unset LDFLAGS CFLAGS CPPFLAGS

	case ${PLATFORM} in
		'RZV2H-RDK')
			# U-Boot has no shared defconfig
			UBOOT_DEFCONFIG="rzv2h-rdk-ver101_defconfig"
			;;
		*)
			echo "Warning: Platform '${PLATFORM}' not recognised or do not have specific defconfig for this platform. Falling back to 'rzv2h-rdk-ver101_defconfig'." >&2
			UBOOT_DEFCONFIG="rzv2h-rdk-ver101_defconfig"
			;;
	esac
}

# Copy the just-built binaries into RELEASE_OUTPUT_DIR/<board-variant>/
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

mk_full_image() {
	mk_reset_src
	uboot_setup
	make "${UBOOT_DEFCONFIG}"
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
	mk_reset_src
	uboot_setup
	make "${UBOOT_DEFCONFIG}"
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
	'all')
		mk_full_image
		;;
	*)
		show_help
		;;
esac

exit 0
