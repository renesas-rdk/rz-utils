#!/bin/bash
# Build 88x2bu.ko, the out-of-tree Realtek RTL8812BU/8822BU USB WiFi driver.
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

NAME="88x2bu"
URL="${WIFI_88X2BU_URL:-https://github.com/morrownr/88x2bu-20210702.git}"
SRCREV="${WIFI_88X2BU_SRCREV:-d31ffa827bb95b8a436c2a469b5163b634ac4333}"
SRC_DIR="${EXT_MODULES_SRC_DIR}/${NAME}"

mk_fetch() {
	ensure_git_src "${NAME}" "${URL}" "${SRCREV}"
}

mk_build() {
	kernel_is_built
	mk_fetch
	echo "--- building ${NAME}"
	local kver
	kver="$(kernel_release)"
	( unset CFLAGS CPPFLAGS CXXFLAGS
	  cd "${SRC_DIR}" && make -j"$(nproc)" \
		ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" \
		KSRC="${KERNEL_DIR}" KVER="${kver}" \
		modules ) || exit 1
}

mk_install() {
	mk_build
	echo '|============================================|'
	echo '|       Install out-of-tree modules          |'
	echo '|============================================|'
	install_module_ko "${NAME}" "${SRC_DIR}" "extra"
}

mk_clean() {
	[ -d "${SRC_DIR}" ] || return 0
	local kver
	kver="$(kernel_release)"
	( cd "${SRC_DIR}" && make ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" \
		KSRC="${KERNEL_DIR}" KVER="${kver}" clean ) || true
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
