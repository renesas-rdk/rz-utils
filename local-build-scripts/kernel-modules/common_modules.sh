#!/bin/bash
# Shared helpers for kernel-modules/build_*.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_ROOT="${SCRIPT_DIR}/patches"

# Source params
source "${SCRIPT_DIR}/config.ini"

EXT_MODULES_SRC_DIR="${EXT_MODULES_SRC_DIR:-$WORKDIR/ext-modules}"

export ARCH="${ARCH:-arm64}"
export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"

# Must match build_kernel.sh's LOCALVERSION
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

# Apply patches
apply_patches() {
	local name="$1" dir="$2" strip="${3:-1}"
	local list_var="${name^^}_PATCHES"

	if ! declare -p "${list_var}" >/dev/null 2>&1; then
		echo "  no patch list ${list_var} for ${name}, skipping"
		return 0
	fi

	local -n patches_ref="${list_var}"
	local p
	for p in "${patches_ref[@]}"; do
		[ -z "${p}" ] && continue
		if ! patch -p"${strip}" -d "${dir}" --no-backup-if-mismatch -i "${PATCH_ROOT}/${name}/${p}" >/dev/null; then
			echo "Error: failed to apply ${name}/${p}"
			exit 1
		fi
		echo "  applied ${p}"
	done
}

# Stable hash of a module's patch list
patches_hash() {
	local name="$1"
	local list_var="${name^^}_PATCHES"

	if ! declare -p "${list_var}" >/dev/null 2>&1; then
		echo "no-patches"
		return 0
	fi

	local -n patches_ref="${list_var}"
	local p
	{
		printf '%s\n' "${patches_ref[@]}"
		for p in "${patches_ref[@]}"; do
			[ -z "${p}" ] && continue
			cat "${PATCH_ROOT}/${name}/${p}"
		done
	} | sha256sum | cut -d' ' -f1
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

# Always checkout matches config.ini
ensure_git_src() {
	local name="$1" url="$2" rev="$3"
	fetch_git "${name}" "${url}" "${rev}"
}

# Download + verify
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
	apply_patches "${name}" "${patch_dir}" "${strip}"
	echo "${sha}:$(patches_hash "${name}")" > "${dir}/.srcrev"
}

# Always re-extract + re-patch
ensure_tar_src() {
	local name="$1" url="$2" sha="$3" patch_dir="${4:-${EXT_MODULES_SRC_DIR}/${name}}" strip="${5:-1}"
	fetch_tar "${name}" "${url}" "${sha}" "${patch_dir}" "${strip}"
}

# make (+ make install) in a module dir
build_module_dir() {
	local name="$1" dir="$2"
	echo "--- building ${name}"
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

# Install every *.ko under $dir into lib/modules/<kver>/<instdir>/ and refresh modules.dep.
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
