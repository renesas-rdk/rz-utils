#!/bin/bash
#
# Build drpai.ko, the DRP-AI accelerator out-of-tree kernel module.
#
# Source: the AI SDK's kernel-module-drpai (rzv2h_ai-sdk_yocto_recipe_v8.00,
# meta-rz-features/meta-rz-drpai), packaged as a vendor/ tarball since there is
# no public upstream repo for it (unlike mmngr/vspm/vspm_if, which are cloned
# straight from GitHub). Not present at all in the renesas-sst
# (yocto_rzcmn_board) tree -- that one patches DRP-AI support directly into
# the kernel instead of shipping it as a separate module (see
# Task/08_Update_rz-utils/Compare_Version/Compare_version.md, item 8). Only
# the v2h variant (DEVICE_NAME=RZV2H) is packaged; v2l/rzv2n are not needed here.
#
# The AI SDK targets kernel 6.1 and ships no kernel-6.18 patch, so two new
# patches were written this session (live cross-build against
# ubuntu/rz-v2h-rdk-rebase-6.18.20, not guessed):
#   0001: gcc 13 rejects "const static" (wants "static const") and warns on a
#         truly-unused non-static helper (reset_cpg) as a missing prototype --
#         both are -Werror in this Makefile, so both are fatal on this
#         toolchain even though they're not kernel-version-specific.
#   0002: four real kernel-6.18 API breaks -- vmalloc()/vfree() need an
#         explicit #include <linux/vmalloc.h> now; DEFINE_SEMAPHORE() takes a
#         count argument; class_create() dropped its owner (THIS_MODULE)
#         argument; platform_driver.remove must return void.
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

NAME="drpai"
DRPAI_TAR="${DRPAI_TAR:-${SCRIPT_DIR}/../../../vendor/drpai_v2h_1.5.0.tar.gz}"
URL="${DRPAI_URL:-file://${DRPAI_TAR}}"
SHA256="${DRPAI_SHA256:-8ac661ea19249f25514853a96cdc7b6afe0d06b99678fee0231d8c5b3f1dd6d7}"
SRC_DIR="${EXT_MODULES_SRC_DIR}/${NAME}"
PKG_DIR="${SRC_DIR}/v2h"
BUILD_SUBDIR="${PKG_DIR}/drivers/drpai"

# The Makefile (copied from Makefile-RZV2H below) drives the kernel's own
# Kbuild itself via $(KERNEL_SRC), the same "own Makefile" pattern as
# mali_kbase and uvcs_drv -- not driven directly with -C $KERNEL_DIR here.
export KERNEL_SRC="${KERNEL_DIR}"

mk_fetch() {
	ensure_tar_src "${NAME}" "${URL}" "${SHA256}" "${SRC_DIR}" 1

	# drpai-core.c/drpai-if.c #include <linux/drpai.h> as a kernel-tree
	# header, not a locally relative one -- the recipe's do_compile()
	# installs it into ${KERNELSRC}/include/{,uapi/}linux/ before building,
	# ported as-is.
	install -d "${KERNEL_DIR}/include/linux" "${KERNEL_DIR}/include/uapi/linux"
	install -m 0644 "${PKG_DIR}/include/linux/drpai.h" "${KERNEL_DIR}/include/linux/"
	install -m 0644 "${PKG_DIR}/include/uapi/linux/drpai.h" "${KERNEL_DIR}/include/uapi/linux/"

	cp "${BUILD_SUBDIR}/Makefile-RZV2H" "${BUILD_SUBDIR}/Makefile"
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
