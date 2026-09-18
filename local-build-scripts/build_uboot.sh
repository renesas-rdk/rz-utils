#!/bin/bash

source ./config.ini
source ./common.sh

# Overrides common.sh's show_help (the full main_build.sh usage covering every
# target) with one scoped to this script, since build_uboot.sh is meant to be
# runnable standalone. Defined after sourcing common.sh so it shadows it.
show_help() {
	cat <<USAGE
Usage: ./build_uboot.sh [sub_command]

Build U-Boot (${UBOOT_DIR}). Called directly or via
'./main_build.sh uboot <sub_command>'.

  <sub_command>:
    clean       make clean
    distclean   make distclean
    defconfig   Write config.ini's DEFCONFIG (make <defconfig>)
    image       make (build using the existing .config, no defconfig step)
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
	echo "There is no U-Boot source at ${UBOOT_DIR} or it does not set properly at config.ini file."
	echo "Please recheck your setup"
	exit 1
fi

# Setup the build
uboot_setup() {
	unset LD_LIBRARY_PATH
	unset LDFLAGS CFLAGS CPPFLAGS

	case ${PLATFORM} in
		'RZ-CMN')
			UBOOT_DEFCONFIG="rz-cmn_defconfig"
			;;
		*)
			echo "Warning: Platform '${PLATFORM}' not recognised or do not have specific defconfig for this platform. Falling back to 'rz-cmn_defconfig'." >&2
			UBOOT_DEFCONFIG="rz-cmn_defconfig"
			;;
	esac
}

mk_image() {
	uboot_setup
	make -j"$(nproc)"
}

mk_full_image() {
	uboot_setup
	make "${UBOOT_DEFCONFIG}"
	make -j"$(nproc)"
}

mk_clean() {
	make clean
}

mk_distclean() {
	make distclean
}

mk_defconfig() {
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
