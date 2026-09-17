#!/bin/bash
#
# Build uvcs_drv.ko, the UVCS (Codec) out-of-tree kernel module.
#
# Source: the AI SDK's versioned tarball (uvcs_kernel_package_v4.3.4.0.tar.bz2),
# not the renesas-sst yocto_rzcmn_board tarball -- that one ships as
# uvcs_kernel_package.tar.bz2 with no version in the filename, so there is no
# way to confirm which revision it actually is (see Compare_Version/Compare_version.md,
# item 5). The AI SDK tarball is confirmed v4.3.4.0.
#
# The AI SDK targets kernel 6.1 and ships no kernel-6.18 patch, so two new
# patches were written this session (live cross-build against
# ubuntu/rz-v2h-rdk-rebase-6.18.20, not guessed):
#   0001: platform_driver.remove must return void (same class of fix as
#         mmngr/mmngrbuf/vspm/vspm_if).
#   0002: del_timer() -> timer_delete(), from_timer() -> timer_container_of()
#         (Linux renamed the old timer API), and
#         devm_reset_control_array_get(dev, false, false) -> the 2-arg form,
#         via the devm_reset_control_array_get_exclusive() convenience wrapper
#         (matches the old call's shared=false/optional=false semantics).
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."
source ./config.ini
source ./common.sh
cd "${SCRIPT_DIR}"
source ./_lib.sh

if [ -z "${KERNEL_DIR:-}" ]; then
	echo "There is no Linux Kernel source at ${KERNEL_DIR:-} or it does not set properly at config.ini file."
	echo "Please recheck your setup"
	exit 1
fi

NAME="uvcs_drv"
UVCS_TAR="${UVCS_TAR:-${SCRIPT_DIR}/../../../vendor/uvcs_kernel_package_v4.3.4.0.tar.bz2}"
URL="${UVCS_URL:-file://${UVCS_TAR}}"
SHA256="${UVCS_SHA256:-a719268bbab3ce13f078158d3ee9b3e7ad1d86c7c04ab8e8ff776e540ecb0738}"
SRC_DIR="${EXT_MODULES_SRC_DIR}/${NAME}"
PKG_DIR="${SRC_DIR}/uvcs_kernel_package"
BUILD_SUBDIR="${PKG_DIR}/src/makefile"

# The vendor Makefile (src/makefile/Makefile) copies from these three
# directories into its own cwd before invoking Kbuild, then deletes the
# copies afterward -- see do_compile:prepend in the AI SDK's
# kernel-module-uvcs-drv.bb, ported as-is.
export UVCS_SRC="${PKG_DIR}/src"
export UVCS_INC="${PKG_DIR}"
export VCP4_SRC="${PKG_DIR}/src"
export KERNELDIR="${KERNEL_DIR}"

mk_fetch() {
	ensure_tar_src "${NAME}" "${URL}" "${SHA256}" "${SRC_DIR}" 1
}

mk_build() {
	kernel_is_built
	mk_fetch
	echo "--- building ${NAME}"
	( unset CFLAGS CPPFLAGS CXXFLAGS
	  cd "${BUILD_SUBDIR}" && make ) || exit 1
}

mk_install() {
	mk_build
	echo '|============================================|'
	echo '|       Install out-of-tree modules          |'
	echo '|============================================|'
	install_module_ko "${NAME}" "${BUILD_SUBDIR}" "extra"
}

mk_clean() {
	[ -d "${BUILD_SUBDIR}" ] || return 0
	( cd "${BUILD_SUBDIR}" && make clean ) || true
}

# ---- Main ----
cmd="${1:-all}"
echo "Starting the ${NAME} module build '${cmd}'"
echo "Source under ${SRC_DIR}"

case "${cmd}" in
	fetch)   mk_fetch ;;
	all)     mk_build ;;
	install) mk_install ;;
	clean)   mk_clean ;;
	*)       show_help ;;
esac

exit 0
