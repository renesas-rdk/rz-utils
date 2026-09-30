#!/bin/bash
# Build mali_kbase.ko, the PowerVR/Mali GPU out-of-tree kernel module, from the Renesas Mali DDK tarball.
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

NAME="mali_kbase"
MALI_DDK_TAR="${MALI_DDK_TAR:-${SCRIPT_DIR}/../../../vendor/mali-g31_km_v1.3.0.tar.gz}"
URL="${MALI_DDK_URL:-file://${MALI_DDK_TAR}}"
SHA256="${MALI_DDK_SHA256:-30d9625e33ab4a52ab9c995bf0e218d65cc909c320bf85c0e60f3572962fb389}"
SRC_DIR="${EXT_MODULES_SRC_DIR}/${NAME}"
BUILD_SUBDIR="mali_km/drivers/gpu/arm/midgard"

export KERNELSRC="${KERNEL_DIR}"
export KERNELDIR="${KERNEL_DIR}"
export KERNEL_SRC="${KERNEL_DIR}"

mk_fetch() {
	# -p5: meta-rz-graphics' patches target a deep path inside the tarball.
	ensure_tar_src "${NAME}" "${URL}" "${SHA256}" "${SRC_DIR}/${BUILD_SUBDIR}" 5

	# Page migration disabled for kernel 6.18 (address_space_operations changed); real stub bodies, not omitted symbols.
	cat > "${SRC_DIR}/${BUILD_SUBDIR}/mali_kbase_mem_migrate.c" <<'EOF'
// SPDX-License-Identifier: GPL-2.0
/* Page migration disabled for kernel 6.18+; real stub bodies since callers don't guard with #ifdef. */
#include <mali_kbase.h>
#include "mali_kbase_mem_migrate.h"

bool kbase_is_page_migration_enabled(void)
{
	return false;
}

bool kbase_alloc_page_metadata(struct kbase_device *kbdev, struct page *p, dma_addr_t dma_addr,
			       u8 group_id)
{
	return false;
}

void kbase_free_page_later(struct kbase_device *kbdev, struct page *p)
{
}

void kbase_mem_migrate_init(struct kbase_device *kbdev)
{
}

void kbase_mem_migrate_term(struct kbase_device *kbdev)
{
}
EOF
}

mk_build() {
	kernel_is_built
	mk_fetch
	echo "--- building ${NAME}"
	( unset CFLAGS CPPFLAGS CXXFLAGS
	  cd "${SRC_DIR}/${BUILD_SUBDIR}" && make -j"$(nproc)" \
		BUILD=release \
		CONFIG_MALI_PLATFORM_NAME=devicetree \
		CONFIG_MALI_MIDGARD=m \
		CONFIG_MALI_DEVFREQ=n \
		CONFIG_MALI_REAL_HW=y ) || exit 1
}

mk_install() {
	mk_build
	echo '|============================================|'
	echo '|       Install out-of-tree modules          |'
	echo '|============================================|'
	install_module_ko "${NAME}" "${SRC_DIR}/${BUILD_SUBDIR}" "extra"
}

mk_clean() {
	[ -d "${SRC_DIR}/${BUILD_SUBDIR}" ] || return 0
	( cd "${SRC_DIR}/${BUILD_SUBDIR}" && make clean ) || true
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
