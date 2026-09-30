#!/bin/bash
# Build vspm.ko, the VSP manager out-of-tree kernel module
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

NAME="vspm"
URL="${VSPM_URL:-https://github.com/renesas-rcar/vspm_drv.git}"
SRCREV="${VSPM_SRCREV:-07787fc1168e7fe37c305aca151a6f756f35874f}"
SUBDIR="vspm-module/files/vspm/drv"
SRC_DIR="${EXT_MODULES_SRC_DIR}/${NAME}"

export KERNELSRC="${KERNEL_DIR}"
export KERNELDIR="${KERNEL_DIR}"
export KERNEL_SRC="${KERNEL_DIR}"
export LDFLAGS=""
export CP="cp"
export INCSHARED="${INCSHARED:-${EXT_MODULES_SRC_DIR}/staging/include}"
mkdir -p "${INCSHARED}"

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
case "${1-}" in
	"all")
		echo "Starting the ${NAME} module build (install)"
		echo "Source under ${SRC_DIR}"
		mk_install
		;;
	"clean")
		echo "Starting the ${NAME} module clean"
		echo "Source under ${SRC_DIR}"
		mk_clean
		;;
	*)
		show_help
		;;
esac

exit 0
