#!/bin/bash
set -euo pipefail

source ./config.ini
source ./common.sh

# if PLATFORM is already exported from main_build.sh, keep it
if [ -n "${PLATFORM:-}" ] && [ -n "${PLAT:-}" ]; then
	PLATFORM="$PLAT"
fi

# Check ATF location
if [ -z "${ATF_DIR}" ]; then
	echo "ATF_DIR is not set properly at config.ini file."
	echo "Please recheck your setup"
	exit 1
fi
ensure_src_dir "${ATF_DIR}" "${ATF_REPO:-}" "${ATF_BRANCH:-}" "TF-A"

# ---- Config ----
JOBS="${JOBS:-$(nproc)}"

# Map PLATFORM -> "PLAT BOARD"
declare -A P2B=(
	["RZ-CMN"]="cmn rz_cmn"
)

# Resolve PLAT/BOARD for a single PLATFORM
resolve_board() {
	local platform="$1"
	if [[ -n "${P2B[$platform]+set}" ]]; then
		read -r PLAT BOARD <<<"${P2B[$platform]}"
	else
		echo "Warning: Platform '$platform' not recognised or do not have specific board config."
		echo "         Falling back to RZ Common System BOARD and PLAT."
		echo "         Note: The common config currently only supports G2L, V2L, and V2H MPUs."
		PLAT="cmn"
		BOARD="rz_cmn"
	fi
	export PLAT BOARD
}

mk_image_one() {
	local platform="$1"
	shift
	local images=("$@")
	resolve_board "${platform}"

	# TF-A's own toolchain.mk undefines LD if left at Make's builtin "default"
	# origin, then re-detects it as CROSS_COMPILE+gcc (ld-id=gnu-gcc), which
	# should get raw linker flags wrapped in -Wl, via its ld_prefix macro. In
	# practice that auto-detection has been unreliable here (BL2 links with
	# --no-dynamic-linker/--emit-relocs unwrapped, hitting "unrecognized
	# command-line option" from gcc) -- pin LD explicitly to force TF-A down
	# the gnu-gcc-linker path it already expects by default.
	if [ "${ATF_MODE:-RELEASE}" = "DEBUG" ]; then
		make -C "${ATF_DIR}" -j"${JOBS}" PLAT="${PLAT}" BOARD="${BOARD}" LD="${CROSS_COMPILE}gcc" DEBUG=1 "${images[@]}"
	else
		make -C "${ATF_DIR}" -j"${JOBS}" PLAT="${PLAT}" BOARD="${BOARD}" LD="${CROSS_COMPILE}gcc" "${images[@]}"
	fi
}

mk_clean_one() {
	local platform="$1"
	resolve_board "${platform}"
	make -C "${ATF_DIR}" -j"${JOBS}" PLAT="${PLAT}" BOARD="${BOARD}" clean || true
}

# Clean all images
mk_distclean_one() {
	make -C "${ATF_DIR}" distclean || true
}

sanitize_env() {
	unset CFLAGS LDFLAGS;
}

# ---- Main ----
cmd="${1:-all}"
echo "Starting the ATF build '${cmd}' (PLATFORM=${PLATFORM}) in ${ATF_DIR}"
sanitize_env

case "${cmd}" in
  clean)      mk_clean_one "${PLATFORM}";;
  distclean)  mk_distclean_one;;
  bl2|bl31|dtbs)
			  mk_image_one "${PLATFORM}" "${cmd}";;
  all)  mk_image_one "${PLATFORM}" "${cmd}" "dtbs";;
  *)
			  show_help ;;
esac

exit 0
