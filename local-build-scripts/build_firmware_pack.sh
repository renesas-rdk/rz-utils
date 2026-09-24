#!/bin/bash
set -euo pipefail

source ./config.ini
source ./common.sh

# Overrides common.sh's show_help (the full main_build.sh usage covering every
# target) with one scoped to this script, since build_firmware_pack.sh is
# meant to be runnable standalone, same as build_uboot.sh/build_atf.sh.
show_help() {
	cat <<USAGE
Usage: ./build_firmware_pack.sh [sub_command]

Packages ATF's BL2/FIP into the boot-header + S-record form the board's
SCIF/Flash-Writer boot flow expects, mirroring meta-renesas's
bptool-native.bb + firmware-pack.bb recipes (see config.ini for the
BPTOOL_*/BL2_*/FIP_* settings this uses).

  <sub_command>:
    bptool      Build the bptool host tool only (from BPTOOL_DIR)
    all         bptool, then build ATF's bl2+fip and package them (default)

Requires U-Boot already built (./build_uboot.sh all) -- BL33=\${UBOOT_DIR}/u-boot.bin
is needed to build ATF's fip target.
USAGE
	exit 1
}

if [ -z "${ATF_DIR}" ]; then
	echo "ATF_DIR is not set properly at config.ini file."
	echo "Please recheck your setup"
	exit 1
fi
if [ -z "${UBOOT_DIR}" ]; then
	echo "UBOOT_DIR is not set properly at config.ini file."
	echo "Please recheck your setup"
	exit 1
fi

JOBS="${JOBS:-$(nproc)}"

# This repo's ATF build only really has one board target today (RZ-CMN's
# PLAT=cmn/BOARD=rz_cmn -- see resolve_board() in build_atf.sh), so this
# stays hardcoded rather than re-deriving it from PLATFORM.
PLAT="cmn"
BOARD="rz_cmn"

BPTOOL_BIN="${BPTOOL_DIR}/tools/renesas/rz_boot_param/bptool"
UBOOT_BIN="${UBOOT_DIR}/u-boot.bin"

sanitize_env() {
	unset CFLAGS LDFLAGS
}

# bptool.c + its Makefile are byte-identical to what ATF_DIR (rz-atf) ships
# at the same tools/renesas/rz_boot_param/ path, but that Makefile also
# `include`s ../../../make_helpers/build_env.mk -- a file ATF_DIR's own
# styhead/rz-cmn branch no longer has (removed upstream by TF-A's "remove
# Windows compatibility layer" commit, which updated every *other* tools/*
# Makefile to match but never touched Renesas's own tools/renesas/* ones).
# So building bptool straight out of ATF_DIR fails with "No rule to make
# target '../../../make_helpers/build_env.mk'" -- BPTOOL_DIR's separately
# pinned, older tree still has it, so that clone stays.
build_bptool() {
	ensure_src_dir_at_rev "${BPTOOL_DIR}" "${BPTOOL_REPO:-}" "${BPTOOL_SRCREV:-}" "bptool"
	echo "Building bptool in ${BPTOOL_DIR}"
	make -C "${BPTOOL_DIR}/tools/renesas/rz_boot_param" bptool DEST_OFFSET_ADR="${BL2_BASE_ADDR}"
}

# Builds ATF's bl2+fip against this repo's own ATF_DIR checkout, same
# PLAT/BOARD/LD as build_atf.sh, plus BL33 so the fip target has a BL33 image
# to bundle -- mirrors TFA_BUILD_TARGET="bl2 fip" in
# meta-rz-bsp/conf/machine/rzv2h-evk.conf.
build_atf_fip() {
	if [ ! -f "${UBOOT_BIN}" ]; then
		echo "Error: ${UBOOT_BIN} not found." >&2
		echo "       Build U-Boot first: ./build_uboot.sh all" >&2
		exit 1
	fi

	sanitize_env
	# See build_atf.sh's mk_image_one() for why LD points at the raw linker
	# instead of CROSS_COMPILE+gcc (rz_common.mk's unwrapped BL2_LDFLAGS).
	make -C "${ATF_DIR}" -j"${JOBS}" PLAT="${PLAT}" BOARD="${BOARD}" \
		LD="${CROSS_COMPILE}ld" BL33="${UBOOT_BIN}" bl2 fip
}

# ATF's own BUILD_PLAT layout under PLAT=cmn/BOARD=rz_cmn hasn't been
# directly confirmed against the real rz-atf tree -- search for the output
# rather than hardcoding a guessed path.
find_atf_output() {
	local name="$1" path
	path="$(find "${ATF_DIR}/build" -type f -name "${name}" -print -quit 2>/dev/null)"
	if [ -z "${path}" ]; then
		echo "Error: could not find ${name} anywhere under ${ATF_DIR}/build" >&2
		echo "       (expected after building bl2+fip -- check ATF's BUILD_PLAT layout)" >&2
		exit 1
	fi
	echo "${path}"
}

mk_pack() {
	build_atf_fip

	local bl2_bin fip_bin
	bl2_bin="$(find_atf_output bl2.bin)"
	fip_bin="$(find_atf_output fip.bin)"

	mkdir -p "${FIRMWARE_PACK_OUTPUT_DIR}"

	local target bp_bin bl2bp_bin
	for target in ${BL2_BOOT_TARGET}; do
		echo "==> Packaging BL2 for boot target '${target}'"
		bp_bin="${FIRMWARE_PACK_OUTPUT_DIR}/bp.bin"
		bl2bp_bin="${FIRMWARE_PACK_OUTPUT_DIR}/bl2_bp_${target}.bin"

		"${BPTOOL_BIN}" "${bl2_bin}" "${bp_bin}" "${BL2_BASE_ADDR}" "${target}"
		cat "${bp_bin}" "${bl2_bin}" > "${bl2bp_bin}"
		objcopy -I binary -O srec --srec-forceS3 --adjust-vma="${BL2_ADJUST_VMA}" \
			"${bl2bp_bin}" "${FIRMWARE_PACK_OUTPUT_DIR}/bl2_bp_${target}.srec"
	done
	rm -f "${bp_bin}"

	echo "==> Packaging FIP"
	cp "${fip_bin}" "${FIRMWARE_PACK_OUTPUT_DIR}/fip-rzv2h-rdk.bin"
	objcopy -I binary -O srec --srec-forceS3 --adjust-vma="${FIP_ADJUST_VMA}" \
		"${fip_bin}" "${FIRMWARE_PACK_OUTPUT_DIR}/fip-rzv2h-rdk.srec"

	echo "======================================"
	echo "Firmware pack finished. Output in ${FIRMWARE_PACK_OUTPUT_DIR}:"
	ls -l "${FIRMWARE_PACK_OUTPUT_DIR}"
	echo "======================================"
}

# ---- Main ----
cmd="${1:-all}"
echo "Starting the firmware pack build '${cmd}'"

case "${cmd}" in
	bptool) build_bptool ;;
	all)    build_bptool; mk_pack ;;
	*)      show_help ;;
esac

exit 0
