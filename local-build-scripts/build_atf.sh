#!/bin/bash
set -euo pipefail

source ./config.ini
source ./common.sh

# Single-board build: PLAT/BOARD come from config.ini (ATF_PLAT/ATF_BOARD) so
# switching board/platform only ever needs editing that file.
if [ -z "${ATF_PLAT:-}" ] || [ -z "${ATF_BOARD:-}" ]; then
	echo "ATF_PLAT/ATF_BOARD are not set in config.ini." >&2
	echo "Please recheck your setup" >&2
	exit 1
fi
PLAT="${ATF_PLAT}"
BOARD="${ATF_BOARD}"

# git -C ./ATF_patches apply <patchfile>
if [ -n "${ATF_PATCH_DIR:-}" ]; then
	ATF_PATCH_DIR="$(cd "${ATF_PATCH_DIR}" && pwd)"
fi

# Check ATF location
if [ -z "${ATF_DIR}" ]; then
	echo "ATF_DIR is not set properly at config.ini file."
	echo "Please recheck your setup"
	exit 1
fi
ensure_src_dir_at_rev "${ATF_DIR}" "${ATF_REPO:-}" "${ATF_SRCREV:-}" "TF-A"

# ---- Board patches from meta-renesas-rdk's trusted-firmware-a recipe ----
# (copied into ATF_PATCH_DIR -- see config.ini's comment there).
COMMON_PATCHES=(
	0001-atf-renesas-build-Suppress-RWX-segment-warning-in-AT.patch
	0002-Bring-GPU-clock-init-back.patch
)
# 8GB-only: DDR/SRAM sizing for the 8GB-RAM board variant. 
PATCHES_8GB=(
	0001-tfa-for-rzv2h-rdk-8GB.patch
	0005-rz-v2h-update-LPDDR4-DDR-parameters-to-vendor-v3.0.3.patch
)

# Reset to the pristine pinned commit
reset_atf_tree() {
	if [ -n "${ATF_SRCREV:-}" ]; then
		git -C "${ATF_DIR}" checkout -q -f "${ATF_SRCREV}"
	fi
}

apply_atf_patches() {
	if [ -z "${ATF_PATCH_DIR:-}" ]; then
		echo "ATF_PATCH_DIR is not set in config.ini -- skipping board patches." >&2
		return 0
	fi
	local p
	for p in "$@"; do
		if [ ! -f "${ATF_PATCH_DIR}/${p}" ]; then
			echo "Error: patch not found: ${ATF_PATCH_DIR}/${p}" >&2
			exit 1
		fi
		echo "Applying ${p}..."
		git -C "${ATF_DIR}" apply "${ATF_PATCH_DIR}/${p}"
	done
}

# ---- Config ----
JOBS="${JOBS:-$(nproc)}"

mk_image() {
	local images=("$@")

	# Make: plat/renesas/rz/common/rz_common.mk 
	LD="${CROSS_COMPILE}ld"
	if [ "${ATF_MODE:-RELEASE}" = "DEBUG" ]; then
		make -C "${ATF_DIR}" -j"${JOBS}" PLAT="${PLAT}" BOARD="${BOARD}" LD="${LD}" DEBUG=1 "${images[@]}"
	else
		make -C "${ATF_DIR}" -j"${JOBS}" PLAT="${PLAT}" BOARD="${BOARD}" LD="${LD}" "${images[@]}"
	fi
}

mk_clean() {
	make -C "${ATF_DIR}" -j"${JOBS}" PLAT="${PLAT}" BOARD="${BOARD}" clean || true
}

mk_distclean() {
	make -C "${ATF_DIR}" distclean || true
}

sanitize_env() {
	unset CFLAGS LDFLAGS;
}

# Builds one RAM variant (8gb|16gb) and copies bl2.bin out of ATF's fixed
# build/${PLAT}/release/ output dir into a variant-tagged name, so building
# the other variant afterward doesn't clobber it.
BUILD_OUT="${ATF_DIR}/build/${PLAT}/release"
build_variant() {
	local variant="$1"
	echo "===== Building ATF for the ${variant} RAM variant ====="
	reset_atf_tree
	apply_atf_patches "${COMMON_PATCHES[@]}"
	if [ "${variant}" = "8gb" ]; then
		apply_atf_patches "${PATCHES_8GB[@]}"
	fi
	mk_clean
	mk_image "bl2" "dtbs"
	cp "${BUILD_OUT}/bl2.bin" "${BUILD_OUT}/bl2-${variant}.bin"
	echo "===== ${variant}: ${BUILD_OUT}/bl2-${variant}.bin ====="
}

# ---- Main ----
cmd="${1:-all}"
echo "Starting the ATF build '${cmd}' (PLAT=${PLAT} BOARD=${BOARD}) in ${ATF_DIR}"
sanitize_env

case "${cmd}" in
  clean)      reset_atf_tree; mk_clean;;
  distclean)  mk_distclean;;
  8gb)        build_variant "8gb";;
  16gb)       build_variant "16gb";;
  all)        build_variant "16gb";;
  *)
              show_help ;;
esac

exit 0
