#!/bin/bash
#
# Deploy the libmali userspace GPU stack (libEGL, libGLESv2, libGLESv1_CM, libOpenCL,
# libgbm, libwayland-egl, and the core libmali.so) into a target rootfs -- e.g. the
# board's NFS root, or a mounted SD image -- so mali_kbase.ko (built by
# kernel-modules/build_mali_kbase.sh) has a userspace driver to talk to.
#
# This is userspace, not a kernel module, so it lives here as its own script rather than
# under kernel-modules/ -- the two are companions (mali_kbase.ko without this loads fine
# but nothing can use the GPU; this without mali_kbase.ko has nothing to talk to).
#
# Source: the libmali-v2h-wayland-gbm .deb that ubuntu_installer's
# deb_create/create_tool/rzv2h_rdk/libmali-v2h-deb/ builds (a prebuilt copy already lives
# in deb_create/pre_built/rzv2h_rdk/ and in ubuntu_installer/oss/ once staged). Point
# LIBMALI_DEB at a local copy (defaults to vendor/libmali-v2h-wayland-gbm_1.3.0-1_arm64.deb
# alongside this checkout, matching build_mali_kbase.sh's DDK tarball convention) or
# export a different path.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBMALI_DEB="${LIBMALI_DEB:-${SCRIPT_DIR}/../../vendor/libmali-v2h-wayland-gbm_1.3.0-1_arm64.deb}"

usage() {
	cat <<USAGE
Usage: $0 <target-rootfs-dir>

Extracts libmali's userspace libs into <target-rootfs-dir>/usr/lib/aarch64-linux-gnu/
(plus its /etc/ld.so.conf.d entry), so a booted rootfs -- e.g. the board's NFS root at
lab 7 (/tftpboot/.../nfs) -- picks it up after running ldconfig on the target.

  LIBMALI_DEB=/path/to/libmali-v2h-wayland-gbm_*.deb   (default: ${LIBMALI_DEB})

Example:
  ./deploy_libmali.sh /tftpboot/sonnguyen/v2h_rdk/nfs
  # then, on the target (over its serial console, or via chroot):
  ldconfig
  LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu/mali your-gl-or-cl-program
USAGE
	exit 1
}

[ -n "${1:-}" ] || usage
TARGET="$1"

[ -f "${LIBMALI_DEB}" ] || { echo "Error: LIBMALI_DEB not found at ${LIBMALI_DEB}"; exit 1; }
[ -d "${TARGET}" ] || { echo "Error: target rootfs dir ${TARGET} does not exist"; exit 1; }
command -v dpkg-deb >/dev/null || { echo "Error: dpkg-deb not found (needed to extract the .deb)"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

echo "Extracting $(basename "${LIBMALI_DEB}")..."
dpkg-deb -x "${LIBMALI_DEB}" "${WORK}"

# A tree that passed through a non-Linux hop (e.g. checked out via a Windows git client)
# can have its symlinks turned into plain-text placeholder files containing the link
# target instead of real symlinks -- the dynamic linker then refuses to load them ("file
# format not recognized; treating as linker script"). Detect and fix that defensively,
# in case LIBMALI_DEB was re-vendored from such a source rather than extracted here.
find "${WORK}" -type f -size -100c | while read -r f; do
	content="$(cat "${f}" 2>/dev/null || true)"
	dir="$(dirname "${f}")"
	if [ -n "${content}" ] && [ -f "${dir}/${content}" ] && [ "${content}" != "$(basename "${f}")" ]; then
		echo "  fixing mangled symlink: ${f#"${WORK}"/} -> ${content}"
		rm "${f}"
		ln -s "${content}" "${f}"
	fi
done

echo "Installing into ${TARGET}..."
mkdir -p "${TARGET}/usr/lib/aarch64-linux-gnu" "${TARGET}/etc/ld.so.conf.d"
cp -a "${WORK}/usr/lib/aarch64-linux-gnu/." "${TARGET}/usr/lib/aarch64-linux-gnu/"
cp -a "${WORK}/etc/ld.so.conf.d/." "${TARGET}/etc/ld.so.conf.d/"

echo "Installed:"
find "${TARGET}/usr/lib/aarch64-linux-gnu" -maxdepth 2 \( -name 'libmali.so' -o -path '*/mali/*' \) -printf '  %P\n' | sort

echo ""
echo "Run 'ldconfig' on the target (or via chroot) to pick it up, then verify with, e.g.:"
echo "  LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu/mali clinfo"
