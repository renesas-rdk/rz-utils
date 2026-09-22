#!/bin/bash
#
# Build vspm_if.ko, the VSPM interface out-of-tree kernel module that
# meta-renesas packages as recipe kernel-module-vspmif.
#
# Source: renesas-rcar/vspmif_drv.git, at the revision meta-renesas pins,
# patched with patches/vspm_if/.
#
# Depends on vspm being built first: vspm_if.ko #includes vspm_public.h and
# links against vspm's Module.symvers (staged by build_vspm.sh as
# ${KERNEL_DIR}/include/vspm.symvers) -- run ./build_vspm.sh all before this.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."
source ./config.ini
source ./common.sh
cd "${SCRIPT_DIR}"
source ./common.sh

if [ -z "${KERNEL_DIR:-}" ]; then
	echo "There is no Linux Kernel source at ${KERNEL_DIR:-} or it does not set properly at config.ini file."
	echo "Please recheck your setup"
	exit 1
fi

NAME="vspm_if"
URL="${VSPMIF_URL:-https://github.com/renesas-rcar/vspmif_drv.git}"
SRCREV="${VSPMIF_SRCREV:-2fdb2838a5625e4231f1cff5d10079acc4954952}"
SUBDIR="vspm_if-module/files/vspm_if/drv"
SRC_DIR="${EXT_MODULES_SRC_DIR}/${NAME}"

export KERNELSRC="${KERNEL_DIR}"
export KERNELDIR="${KERNEL_DIR}"
export KERNEL_SRC="${KERNEL_DIR}"
export LDFLAGS=""
export CP="cp"
export INCSHARED="${INCSHARED:-${EXT_MODULES_SRC_DIR}/staging/include}"
mkdir -p "${INCSHARED}"

vspm_is_built() {
	if [ ! -f "${KERNEL_DIR}/include/vspm.symvers" ]; then
		echo "Error: ${KERNEL_DIR}/include/vspm.symvers not found."
		echo "       vspm_if links against vspm -- build it first: ./build_vspm.sh all"
		exit 1
	fi
}

mk_fetch() {
	ensure_git_src "${NAME}" "${URL}" "${SRCREV}"
}

mk_build() {
	kernel_is_built
	vspm_is_built
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
