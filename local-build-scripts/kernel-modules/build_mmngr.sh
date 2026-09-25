#!/bin/bash
# Build mmngr.ko, the memory manager out-of-tree kernel module
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."
source ./config.ini
source ./common.sh
cd "${SCRIPT_DIR}"
source ./common_modules.sh

if [ -z "${KERNEL_DIR:-}" ]; then
	echo "There is no Linux Kernel source at ${KERNEL_DIR:-} or it does not set properly at config.ini file."
	echo "Please recheck your setup"
	exit 1
fi

NAME="mmngr"
URL="${MMNGR_URL:-https://github.com/renesas-rcar/mmngr_drv.git}"
SRCREV="${MMNGR_SRCREV:-2439802426474136312bd10bc4c143fbf1c84850}"
SUBDIR="mmngr_drv/mmngr/mmngr-module/files/mmngr/drv"
SRC_DIR="${EXT_MODULES_SRC_DIR}/${NAME}"

# The environment the recipe sets through the module bbclass.
export KERNELSRC="${KERNEL_DIR}"
export KERNELDIR="${KERNEL_DIR}"
export KERNEL_SRC="${KERNEL_DIR}"
export LDFLAGS=""
export CP="cp"

export INCSHARED="${INCSHARED:-${EXT_MODULES_SRC_DIR}/staging/include}"
mkdir -p "${INCSHARED}"

export MMNGR_CONFIG="${MMNGR_CONFIG:-MMNGR_SALVATORX}"
export MMNGR_SSP_CONFIG="${MMNGR_SSP_CONFIG:-MMNGR_SSP_DISABLE}"
export MMNGR_IPMMU_MMU_CONFIG="${MMNGR_IPMMU_MMU_CONFIG:-IPMMU_MMU_DISABLE}"

mk_fetch() {
	ensure_git_src "${NAME}" "${URL}" "${SRCREV}"
}

mk_build() {
	kernel_is_built
	mk_fetch
	build_module_dir "${NAME}" "${SRC_DIR}/${SUBDIR}"
}

mk_install() {
	mk_build
	echo '|============================================|'
	echo '|       Install out-of-tree modules          |'
	echo '|============================================|'
	install_module_ko "${NAME}" "${SRC_DIR}/${SUBDIR}" "extra"
}

mk_clean() {
	[ -d "${SRC_DIR}/${SUBDIR}" ] || return 0
	( unset CFLAGS CPPFLAGS CXXFLAGS
	  cd "${SRC_DIR}/${SUBDIR}" && make clean ) || true
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
