#!/bin/bash
#
# Build mali_kbase.ko, the PowerVR/Mali GPU out-of-tree kernel module, from
# the Renesas Mali DDK tarball (mali-g31_km_v1.3.0.tar.gz).
#
# Started as a port of Task 06's build_mali_module.sh (same patches, DDK
# tarball, and page-migration idea, cross-compiled with aarch64-linux-gnu-
# instead of the SDK) -- but that script drove the kernel's Kbuild directly
# (`make -C $KERNEL_DIR M=...`), which skips the DDK's own Makefile and with
# it the translation of CONFIG_MALI_* into real -D flags. That produced a
# mali_kbase.ko that *links* but fails `insmod` for real on hardware ("Unknown
# symbol"); Task 06 never actually insmod-tested it. Fixed here by building
# via the DDK's own Makefile (cd in, plain `make`) and adding real stub bodies
# for the page-migration functions instead of an empty .c file -- see the
# comments in mk_fetch/mk_build below.
#
# The DDK tarball is a proprietary Renesas download, not a public URL: point
# MALI_DDK_TAR at a local copy (defaults to vendor/ alongside this checkout, so
# it resolves both on the bare lab157 host and inside any container that only
# bind-mounts the ubuntu_24 tree, e.g. son_ubuntu_24) or export
# MALI_DDK_URL=file://... yourself.
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
	# meta-rz-graphics' patches for this DDK are against a deep path inside
	# the tarball, hence -p5 (see build_mali_module.sh, the script this was
	# ported from).
	ensure_tar_src "${NAME}" "${URL}" "${SHA256}" "${SRC_DIR}/${BUILD_SUBDIR}" 5

	# Page migration is not patched, it's disabled outright: kernel 6.18
	# changed address_space_operations completely and the DDK's migration
	# callbacks no longer match any signature worth patching around. Real
	# (non-empty) stub bodies are required -- mali_kbase_mem_pool.c/mem.c
	# call these unconditionally behind kbase_is_page_migration_enabled(),
	# so returning false/no-op from it disables the feature cleanly instead
	# of leaving the symbols undefined (which only "works" because
	# KBUILD_MODPOST_WARN=1 downgrades the link error to a warning --
	# insmod then fails for real with "Unknown symbol").
	cat > "${SRC_DIR}/${BUILD_SUBDIR}/mali_kbase_mem_migrate.c" <<'EOF'
// SPDX-License-Identifier: GPL-2.0
/*
 * Page migration disabled for kernel 6.18+: address_space_operations changed
 * completely upstream and the DDK's migration callbacks (this file, as
 * shipped) no longer match any signature worth patching around. These are
 * real stub bodies, not omitted definitions -- kbase_is_page_migration_enabled()
 * returning false is what actually disables the feature; the other four
 * still need a symbol to link against since mali_kbase_mem_pool.c and
 * mali_kbase_mem.c call them unconditionally (guarded at the call site by
 * kbase_is_page_migration_enabled(), not by a compile-time #ifdef).
 */
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
	# Build via the DDK's OWN top-level Makefile (cd in, plain `make`), not by
	# driving the kernel's Kbuild directly with `make -C $KERNEL_DIR M=...`.
	# That distinction matters here, unlike for mmngr/vspm: this Makefile
	# computes CONFIG_MALI_* (from CONFIGS, see its own Makefile) into
	# -DCONFIG_MALI_X=1 flags and passes them to the kernel build as
	# KCPPFLAGS -- driving Kbuild directly skips that translation entirely,
	# so every `#if IS_ENABLED(CONFIG_MALI_...)` in the driver evaluates as
	# if unset, no matter what CONFIG_MALI_*=y we pass as `make` variables.
	# That's what caused device/backend/mali_kbase_device_jm.c's dev_init[]
	# table to wire up kbase_gpu_device_create/destroy from the (correctly
	# excluded) dummy-model backend instead of the real-hardware path
	# (kbase_get_irqs/registers_map) -- an "Unknown symbol" at insmod time
	# on real hardware despite a clean build, because KBUILD_MODPOST_WARN=1
	# only downgrades the link error to a warning, it doesn't fix it.
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
