#!/bin/bash
set -euo pipefail

source ./config.ini
source ./common.sh

# Overrides common.sh's show_help with one scoped to this script.
show_help() {
	cat <<USAGE
Usage: ./build_firmware_pack.sh [sub_command]

  <sub_command>:
    bptool      Build the bptool host tool only (from BPTOOL_DIR)
    ver1        Package the 16GB-RAM board variant only
    ver101      Package the 8GB-RAM board variant only
    all         bptool, then package both ver1 and ver101 (default)

USAGE
	exit 1
}

if [ -z "${ATF_DIR}" ]; then
	echo "ATF_DIR is not set properly at config.ini file."
	echo "Please recheck your setup"
	exit 1
fi
if [ -z "${RELEASE_OUTPUT_DIR:-}" ]; then
	echo "RELEASE_OUTPUT_DIR is not set in config.ini." >&2
	exit 1
fi

JOBS="${JOBS:-$(nproc)}"

# PLAT/BOARD come from config.ini
if [ -z "${ATF_PLAT:-}" ] || [ -z "${ATF_BOARD:-}" ]; then
	echo "ATF_PLAT/ATF_BOARD are not set in config.ini." >&2
	exit 1
fi
PLAT="${ATF_PLAT}"
BOARD="${ATF_BOARD}"

if [ -n "${ATF_PATCH_DIR:-}" ]; then
	ATF_PATCH_DIR="$(cd "${ATF_PATCH_DIR}" && pwd)"
fi

BPTOOL_BIN="${BPTOOL_DIR}/tools/renesas/rz_boot_param/bptool"

sanitize_env() {
	unset CFLAGS LDFLAGS
}

# bptool built from BPTOOL_DIR, not ATF_DIR: ATF_DIR's Makefile include is missing on this branch.
build_bptool() {
	ensure_src_dir_at_rev "${BPTOOL_DIR}" "${BPTOOL_REPO:-}" "${BPTOOL_SRCREV:-}" "bptool"
	echo "Building bptool in ${BPTOOL_DIR}"
	make -C "${BPTOOL_DIR}/tools/renesas/rz_boot_param" bptool DEST_OFFSET_ADR="${BL2_BASE_ADDR}"
}

# config.ini's ATF_SRCREV_<VARIANT> overrides the shared ATF_SRCREV fallback --
# same per-variant resolution as build_atf.sh's resolve_srcrev().
resolve_srcrev() {
	local variant="$1"
	local varname="ATF_SRCREV_${variant^^}"
	local rev="${!varname:-}"
	if [ -z "${rev}" ]; then
		rev="${ATF_SRCREV:-}"
	fi
	if [ -z "${rev}" ]; then
		echo "Error: no ${varname} (or fallback ATF_SRCREV) set in config.ini." >&2
		exit 1
	fi
	echo "${rev}"
}

reset_atf_tree() {
	local rev="$1"
	git -C "${ATF_DIR}" checkout -q -f "${rev}"
}

# Same per-variant patch directory convention as build_atf.sh.
apply_variant_patches() {
	local variant="$1"
	local dir="${ATF_PATCH_DIR}/rz-v2h-rdk-${variant}"
	local arrname="ATF_PATCHES_${variant^^}"
	if ! declare -p "${arrname}" &>/dev/null; then
		echo "Error: ${arrname} is not set in config.ini." >&2
		exit 1
	fi
	local -n patches="${arrname}"
	local p
	for p in "${patches[@]}"; do
		if [ ! -f "${dir}/${p}" ]; then
			echo "Error: patch not found: ${dir}/${p}" >&2
			exit 1
		fi
		echo "Applying ${p}..."
		git -C "${ATF_DIR}" apply "${dir}/${p}"
	done
}

# Builds ATF's bl2+fip for one variant, bundling that variant's own U-Boot as BL33.
build_atf_fip() {
	local variant="$1"
	local uboot_bin="${RELEASE_OUTPUT_DIR}/rzv2h-rdk-${variant}/u-boot.bin"
	if [ ! -f "${uboot_bin}" ]; then
		echo "Error: ${uboot_bin} not found." >&2
		echo "       Build U-Boot for the ${variant} variant first -- see --help." >&2
		exit 1
	fi

	local rev
	rev="$(resolve_srcrev "${variant}")"
	ensure_src_dir_at_rev "${ATF_DIR}" "${ATF_REPO:-}" "${rev}" "TF-A"
	reset_atf_tree "${rev}"
	apply_variant_patches "${variant}"
	sanitize_env
	# LD points at the raw linker, not CROSS_COMPILE+gcc -- see build_atf.sh.
	make -C "${ATF_DIR}" -j"${JOBS}" PLAT="${PLAT}" BOARD="${BOARD}" \
		LD="${CROSS_COMPILE}ld" BL33="${uboot_bin}" bl2 fip
}

BUILD_OUT="${ATF_DIR}/build/${PLAT}/release"

mk_pack() {
	local variant="$1"
	local outdir="${RELEASE_OUTPUT_DIR}/rzv2h-rdk-${variant}"
	build_atf_fip "${variant}"

	local bl2_bin="${BUILD_OUT}/bl2.bin" fip_bin="${BUILD_OUT}/fip.bin"
	[ -f "${bl2_bin}" ] || { echo "Error: ${bl2_bin} missing after build" >&2; exit 1; }
	[ -f "${fip_bin}" ] || { echo "Error: ${fip_bin} missing after build" >&2; exit 1; }

	mkdir -p "${FIRMWARE_PACK_OUTPUT_DIR}" "${outdir}"

	local target bp_bin bl2bp_bin
	for target in ${BL2_BOOT_TARGET}; do
		echo "==> [${variant}] Packaging BL2 for boot target '${target}'"
		bp_bin="${FIRMWARE_PACK_OUTPUT_DIR}/bp.bin"
		bl2bp_bin="${FIRMWARE_PACK_OUTPUT_DIR}/bl2_bp_${target}.bin"

		"${BPTOOL_BIN}" "${bl2_bin}" "${bp_bin}" "${BL2_BASE_ADDR}" "${target}"
		cat "${bp_bin}" "${bl2_bin}" > "${bl2bp_bin}"
		objcopy -I binary -O srec --srec-forceS3 --adjust-vma="${BL2_ADJUST_VMA}" \
			"${bl2bp_bin}" "${bl2bp_bin%.bin}.srec"
		cp "${bl2bp_bin}" "${bl2bp_bin%.bin}.srec" "${outdir}/"
	done
	rm -f "${bp_bin}"

	echo "==> [${variant}] Packaging FIP"
	local fip_out="${FIRMWARE_PACK_OUTPUT_DIR}/fip.bin"
	cp "${fip_bin}" "${fip_out}"
	objcopy -I binary -O srec --srec-forceS3 --adjust-vma="${FIP_ADJUST_VMA}" \
		"${fip_out}" "${fip_out%.bin}.srec"
	cp "${fip_out}" "${fip_out%.bin}.srec" "${outdir}/"

	echo "===== [${variant}] firmware pack done, published to ${outdir} ====="
}

# ---- Main ----
cmd="${1:-all}"
echo "Starting the firmware pack build '${cmd}'"

case "${cmd}" in
	bptool) build_bptool ;;
	ver1)   build_bptool; mk_pack ver1 ;;
	ver101) build_bptool; mk_pack ver101 ;;
	all)    build_bptool; mk_pack ver1; mk_pack ver101 ;;
	*)      show_help ;;
esac

exit 0
