#!/bin/bash
#
# Shared helpers for kernel-modules/build_*.sh. Each build_<name>.sh sources
# ../config.ini and ../common.sh first (for KERNEL_DIR, KERNEL_MODULES_OUTPUT_DIR,
# show_help), then this file.
#
# Ported from Task 05's build_ext_modules.sh, split out of its EXT_MODULES table
# so each module gets its own standalone script instead.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_ROOT="${SCRIPT_DIR}/patches"

# Default now lives in config.ini (keyed off WORKDIR, like every other *_DIR
# there) -- already sourced by the caller before this file. Kept here too,
# defensively, in case this is ever sourced without config.ini.
EXT_MODULES_SRC_DIR="${EXT_MODULES_SRC_DIR:-$WORKDIR/ext-modules}"

# main_build.sh exports these; default them so a build_<name>.sh also works when
# run directly. Without them the modules build with the host gcc and the kernel
# refuses them ("the compiler differs from the one used to build the kernel").
export ARCH="${ARCH:-arm64}"
export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"

# Must match build_kernel.sh: without it scripts/setlocalversion appends a '+'
# and the modules would land in a different /lib/modules/<release> directory
# than the in-tree ones.
export LOCALVERSION=""

kernel_is_built() {
	if [ ! -f "${KERNEL_DIR}/Module.symvers" ]; then
		echo "Error: ${KERNEL_DIR}/Module.symvers not found."
		echo "       External modules link against the kernel build, so build it"
		echo "       first: ./main_build.sh kernel modules-install"
		exit 1
	fi
}

kernel_release() {
	make -s -C "${KERNEL_DIR}" kernelrelease 2>/dev/null | tail -1
}

# Apply the patches listed in patches/<name>/series, in that order. The order
# matters and is not alphabetical, it mirrors the recipe's SRC_URI. Strip
# level defaults to 1 (git-style a/ b/ patches); mali_kbase's DDK tarball
# patches need -p5, hence the third argument.
apply_patches() {
	local name="$1" dir="$2" strip="${3:-1}"
	local series="${PATCH_ROOT}/${name}/series"

	if [ ! -f "${series}" ]; then
		echo "  no patch series for ${name}, skipping"
		return 0
	fi

	local p
	while read -r p; do
		[ -z "${p}" ] && continue
		case "${p}" in \#*) continue;; esac
		if ! patch -p"${strip}" -d "${dir}" --no-backup-if-mismatch -i "${PATCH_ROOT}/${name}/${p}" >/dev/null; then
			echo "Error: failed to apply ${name}/${p}"
			exit 1
		fi
		echo "  applied ${p}"
	done < "${series}"
}

fetch_git() {
	local name="$1" url="$2" rev="$3"
	local dir="${EXT_MODULES_SRC_DIR}/${name}"

	if [ ! -d "${dir}/.git" ]; then
		echo "Cloning ${url} -> ${dir}"
		mkdir -p "${EXT_MODULES_SRC_DIR}"
		git clone -q "${url}" "${dir}" || exit 1
	fi

	if ! git -C "${dir}" cat-file -e "${rev}^{commit}" 2>/dev/null; then
		git -C "${dir}" fetch -q --all --tags || exit 1
	fi

	echo "Checking out ${name} at ${rev}"
	git -C "${dir}" checkout -q -f "${rev}" || exit 1
	git -C "${dir}" clean -qxfd || exit 1
	apply_patches "${name}" "${dir}"
}

# Only re-fetch when the source is missing or sits on a different revision, so
# "all" can be re-run without throwing away an already patched tree.
ensure_git_src() {
	local name="$1" url="$2" rev="$3"
	local dir="${EXT_MODULES_SRC_DIR}/${name}"
	local have

	have="$(git -C "${dir}" rev-parse HEAD 2>/dev/null)"
	if [ -n "${have}" ] && [ "${have}" = "${rev}" ]; then
		echo "${name}: already at ${rev}"
		return 0
	fi
	fetch_git "${name}" "${url}" "${rev}"
}

# Download and verify a tarball into the downloads cache, echoing its path.
# A local file:// URL is accepted for proprietary packages that ship inside a
# Yocto meta-layer rather than a public download.
fetch_tarball() {
	local url="$1" sha="$2"
	local dl="${EXT_MODULES_SRC_DIR}/downloads"
	local tarball="${dl}/$(basename "${url%%;*}")"

	mkdir -p "${dl}"
	if [ ! -f "${tarball}" ] || [ "$(sha256sum "${tarball}" | cut -d' ' -f1)" != "${sha}" ]; then
		case "${url}" in
			file://*) cp "${url#file://}" "${tarball}" || return 1 ;;
			*)
				echo "Downloading ${url}" >&2
				curl -fsSL -o "${tarball}" "${url}" || return 1
				;;
		esac
	fi

	local got
	got="$(sha256sum "${tarball}" | cut -d' ' -f1)"
	if [ "${got}" != "${sha}" ]; then
		echo "Error: checksum mismatch for ${tarball}" >&2
		echo "       expected ${sha}" >&2
		echo "       got      ${got}" >&2
		return 1
	fi
	echo "${tarball}"
}

fetch_tar() {
	local name="$1" url="$2" sha="$3" patch_dir="${4:-${EXT_MODULES_SRC_DIR}/${name}}" strip="${5:-1}"
	local dir="${EXT_MODULES_SRC_DIR}/${name}"
	local tarball

	tarball="$(fetch_tarball "${url}" "${sha}")" || exit 1

	echo "Extracting ${name}"
	rm -rf "${dir}"
	mkdir -p "${dir}"
	tar xf "${tarball}" -C "${dir}" || exit 1
	echo "${sha}" > "${dir}/.srcrev"
	apply_patches "${name}" "${patch_dir}" "${strip}"
}

ensure_tar_src() {
	local name="$1" url="$2" sha="$3" patch_dir="${4:-${EXT_MODULES_SRC_DIR}/${name}}" strip="${5:-1}"
	local dir="${EXT_MODULES_SRC_DIR}/${name}"
	local have

	have="$(cat "${dir}/.srcrev" 2>/dev/null)"
	if [ -n "${have}" ] && [ "${have}" = "${sha}" ]; then
		echo "${name}: already at ${sha}"
		return 0
	fi
	fetch_tar "${name}" "${url}" "${sha}" "${patch_dir}" "${strip}"
}

# make in a module dir, then `make install` if the Makefile has that target
# (this is what the Yocto recipes' do_install runs: it publishes the module's
# public headers into ${KERNELSRC}/include), then stage Module.symvers as
# <name>.symvers for modules that link against this one (e.g. vspm_if passes
# KBUILD_EXTRA_SYMBOLS=${KERNELSRC}/include/vspm.symvers).
build_module_dir() {
	local name="$1" dir="$2"
	echo "--- building ${name}"
	# The Makefiles pass M=$(PWD) to the kernel build, and `make -C` does not
	# update PWD, so cd in rather than using -C.
	( unset CFLAGS CPPFLAGS CXXFLAGS
	  cd "${dir}" && make -j"$(nproc)" ) || exit 1

	if grep -qE "^install:" "${dir}/Makefile" 2>/dev/null; then
		( unset CFLAGS CPPFLAGS CXXFLAGS
		  cd "${dir}" && make install ) || exit 1
	fi

	if [ -f "${dir}/Module.symvers" ]; then
		install -m 644 "${dir}/Module.symvers" "${KERNEL_DIR}/include/${name}.symvers" || exit 1
	fi
}

# Install every *.ko under $dir into KERNEL_MODULES_OUTPUT_DIR/lib/modules/<kver>/<instdir>/
# and refresh modules.dep. build_kernel.sh runs "make INSTALL_MOD_PATH=... modules_install"
# before any of these out-of-tree modules exist, so depmod has to be re-run here.
install_module_ko() {
	local name="$1" dir="$2" instdir="$3"

	if [ -z "${KERNEL_MODULES_OUTPUT_DIR:-}" ]; then
		echo "KERNEL_MODULES_OUTPUT_DIR is not set in config.ini."
		exit 1
	fi

	local kver
	kver="$(kernel_release)"
	if [ -z "${kver}" ]; then
		echo "Error: could not determine the kernel release from ${KERNEL_DIR}"
		exit 1
	fi

	local ko
	for ko in "${dir}/"*.ko; do
		[ -e "${ko}" ] || continue
		install -Dm 644 "${ko}" "${KERNEL_MODULES_OUTPUT_DIR}/lib/modules/${kver}/${instdir}/$(basename "${ko}")"
		echo "  ${instdir}/$(basename "${ko}")"
	done

	local depmod_bin
	depmod_bin="$(command -v depmod 2>/dev/null || true)"
	if [ -z "${depmod_bin}" ]; then
		echo "Error: depmod not found; install kmod before installing external modules."
		exit 1
	fi
	"${depmod_bin}" -b "${KERNEL_MODULES_OUTPUT_DIR}" "${kver}" || exit 1
	echo "  refreshed lib/modules/${kver}/modules.dep"
}
