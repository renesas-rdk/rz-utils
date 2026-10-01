#!/bin/bash
set -euo pipefail

source ./config.ini
source ./common.sh

# Overrides common.sh's show_help with one scoped to this script.
show_help() {
	cat <<USAGE
Usage: ./build_atf.sh [sub_command]

Build TF-A (${ATF_DIR}) for the RZ/V2H RDK board. Each RAM variant can pin
its own upstream commit (config.ini's ATF_SRCREV_VER1 / ATF_SRCREV_VER101,
falling back to ATF_SRCREV if a variant-specific one isn't set) and its own
patch list (config.ini's ATF_PATCHES_VER1 / ATF_PATCHES_VER101, files found
under ATF_PATCH_DIR/rz-v2h-rdk-<variant>/).

  <sub_command>:
    clean       make clean
    distclean   make distclean
    ver1        Build the 16GB-RAM board variant only
    ver101      Build the 8GB-RAM board variant only
    all         Build both ver1 and ver101 (default if no sub_command given)
USAGE
	exit 1
}

# Single-board build: PLAT/BOARD come from config.ini's ATF_PLAT/ATF_BOARD.
if [ -z "${ATF_PLAT:-}" ] || [ -z "${ATF_BOARD:-}" ]; then
	echo "ATF_PLAT/ATF_BOARD are not set in config.ini." >&2
	echo "Please recheck your setup" >&2
	exit 1
fi
PLAT="${ATF_PLAT}"
BOARD="${ATF_BOARD}"

if [ -n "${ATF_PATCH_DIR:-}" ]; then
	ATF_PATCH_DIR="$(cd "${ATF_PATCH_DIR}" && pwd)"
fi

# Check ATF location
if [ -z "${ATF_DIR}" ]; then
	echo "ATF_DIR is not set properly at config.ini file."
	echo "Please recheck your setup"
	exit 1
fi

# config.ini's ATF_SRCREV_<VARIANT> (e.g. ATF_SRCREV_VER1) overrides the
# shared ATF_SRCREV fallback -- lets ver1/ver101 track different upstream
# commits, not just different patches on top of the same one.
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

# Apply config.ini's ATF_PATCHES_<VARIANT> array, in listed order, from
# ATF_PATCH_DIR/rz-v2h-rdk-<variant>/ -- so the full patch set for each board
# is readable straight out of config.ini, not just the directory listing.
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
	unset CFLAGS LDFLAGS
}

# Any rev will do just to have a tree to clean -- clean/distclean aren't
# variant-specific, so don't force picking one.
ensure_atf_dir_exists() {
	local rev
	rev="$(resolve_srcrev ver101)"
	ensure_src_dir_at_rev "${ATF_DIR}" "${ATF_REPO:-}" "${rev}" "TF-A"
}

# Copy bl2.bin into RELEASE_OUTPUT_DIR/rzv2h-rdk-<variant>/ -- same
# per-board-variant subfolder convention as build_uboot.sh's publish_release().
publish_release() {
	local variant="$1"
	local bl2_bin="$2"
	local outdir
	if [ -z "${RELEASE_OUTPUT_DIR:-}" ]; then
		echo "RELEASE_OUTPUT_DIR is not set in config.ini -- skipping release copy." >&2
		return 0
	fi
	outdir="${RELEASE_OUTPUT_DIR}/rzv2h-rdk-${variant}"
	mkdir -p "${outdir}"
	cp "${bl2_bin}" "${outdir}/bl2.bin"
	echo "Published bl2.bin to ${outdir}/"
}

# Builds one RAM variant (ver1|ver101) and copies bl2.bin to a variant-tagged name.
BUILD_OUT="${ATF_DIR}/build/${PLAT}/release"
build_variant() {
	local variant="$1"
	local rev
	rev="$(resolve_srcrev "${variant}")"
	echo "===== Building ATF for the ${variant} RAM variant (TF-A @ ${rev}) ====="
	ensure_src_dir_at_rev "${ATF_DIR}" "${ATF_REPO:-}" "${rev}" "TF-A"
	reset_atf_tree "${rev}"
	apply_variant_patches "${variant}"
	mk_clean
	mk_image "bl2" "dtbs"
	cp "${BUILD_OUT}/bl2.bin" "${BUILD_OUT}/bl2-${variant}.bin"
	publish_release "${variant}" "${BUILD_OUT}/bl2.bin"
	echo "===== ${variant}: ${BUILD_OUT}/bl2-${variant}.bin ====="
}

# ---- Main ----
cmd="${1:-all}"
echo "Starting the ATF build '${cmd}' (PLAT=${PLAT} BOARD=${BOARD}) in ${ATF_DIR}"
sanitize_env

case "${cmd}" in
  clean)      ensure_atf_dir_exists; mk_clean;;
  distclean)  ensure_atf_dir_exists; mk_distclean;;
  ver1)       build_variant "ver1";;
  ver101)     build_variant "ver101";;
  all)        build_variant "ver1"; build_variant "ver101";;
  *)
              show_help ;;
esac

exit 0
