#!/bin/bash

source ./config.ini
source ./common.sh

# Overrides common.sh's show_help with one scoped to this script.
show_help() {
	cat <<USAGE
Usage: ./build_kernel.sh [sub_command]

Build the Linux kernel (${KERNEL_DIR}). Called directly or via
'./main_build.sh kernel <sub_command>'.

  <sub_command>:
    clean             make clean
    distclean         make distclean
    defconfig         Write config.ini's DEFCONFIG (kernel_setup + make <defconfig>)
    menuconfig        defconfig, then make menuconfig
    image             defconfig, then build Image
    dtbs              defconfig, then build device trees
    modules           defconfig + Image + dtbs + build modules
    modules-install   modules, then install into KERNEL_MODULES_OUTPUT_DIR
    all               defconfig + Image + dtbs + modules + modules-install
                      (i.e. everything -- same as modules-install)

Platform override: PLAT=RZV2H-RDK ./build_kernel.sh all
  (defaults to config.ini's PLATFORM, which selects the DEFCONFIG -- see the
  KERN_DEFCONFIG map in this script)
USAGE
	exit 1
}

# if PLATFORM is already exported from main_build.sh, keep it
if [ -n "${PLATFORM:-}" ] && [ -n "${PLAT:-}" ]; then
	PLATFORM="$PLAT"
fi

# Check Linux Kernel location
if [ -z "${KERNEL_DIR}" ]; then
	echo "KERNEL_DIR is not set properly at config.ini file."
	echo "Please recheck your setup"
	exit 1
fi
ensure_src_dir "${KERNEL_DIR}" "${KERNEL_REPO:-}" "${KERNEL_BRANCH:-}" "Linux Kernel"

# Default fallback
DEFCONFIG="renesas_defconfig"

# Per-platform mapping
declare -A KERN_DEFCONFIG=(
	["RZG2L-SBC"]="rzg2l-sbc_defconfig"
	["RZG2L-EVK"]="rzv2l_defconfig"
	["RZV2L-EVK"]="rzv2l_defconfig"
	["RZV2H-EVK"]="rzv2h_defconfig"
	["RZV2H-RDK"]="rzv2h_defconfig"
)

# Resolve DEFCONFIG
if [[ "${PLATFORM}" == "RZ-CMN" ]]; then
	DEFCONFIG="renesas_defconfig"
elif [[ -n "${KERN_DEFCONFIG[$PLATFORM]+x}" ]]; then
	DEFCONFIG="${KERN_DEFCONFIG[$PLATFORM]}"
else
    echo "Warning: Platform '${PLATFORM}' not recognised or do not have a specific defconfig. Falling back to common renesas_defconfig."
    DEFCONFIG="renesas_defconfig"
fi

echo "Using DEFCONFIG=${DEFCONFIG}"

# Optional: KERNEL_VARIANT=<name> merges kernel-config/<name>.config on top of the board defconfig.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARIANT_FRAGMENT=""
if [ -n "${KERNEL_VARIANT:-}" ]; then
	VARIANT_FRAGMENT="${SCRIPT_DIR}/kernel-config/${KERNEL_VARIANT}.config"
	if [ ! -f "${VARIANT_FRAGMENT}" ]; then
		echo "Error: unknown KERNEL_VARIANT '${KERNEL_VARIANT}'."
		echo "       No such fragment: ${VARIANT_FRAGMENT}"
		echo "Available variants:"
		for f in "${SCRIPT_DIR}"/kernel-config/*.config; do
			[ -e "$f" ] || { echo "  (none)"; break; }
			echo "  $(basename "$f" .config)"
		done
		exit 1
	fi
	echo "Using KERNEL_VARIANT=${KERNEL_VARIANT} (${VARIANT_FRAGMENT})"
fi

kernel_setup() {
	export LOCALVERSION=""
}

# Concatenate the board defconfig and the variant fragment, let kconfig fill in the rest.
mk_config_merged() {
	local defconfig_file="arch/arm64/configs/${DEFCONFIG}"

	if [ ! -f "${defconfig_file}" ]; then
		echo "Error: missing kernel config input: ${KERNEL_DIR}/${defconfig_file}"
		exit 1
	fi

	local merged
	merged="$(mktemp -t rzv2h-merged-config.XXXXXX)"
	cat "${defconfig_file}" > "${merged}"
	# Variant fragment goes last so it can override the board defconfig.
	cat "${VARIANT_FRAGMENT}" >> "${merged}"

	echo '|============================================|'
	echo '|      Configure kernel (alldefconfig)       |'
	echo '|============================================|'
	make KCONFIG_ALLCONFIG="${merged}" alldefconfig
	local rc=$?
	rm -f "${merged}"
	if [ ${rc} -ne 0 ]; then
		echo "Error: kernel configuration failed"
		exit ${rc}
	fi
}

# Single choke point for turning DEFCONFIG into a .config, so KERNEL_VARIANT always applies.
configure_kernel() {
	if [ -n "${VARIANT_FRAGMENT}" ]; then
		mk_config_merged
	else
		make ${DEFCONFIG}
	fi
}

mk_image() {
	echo '|============================================|'
	echo '|          Build IMAGE ARM64 RENESAS         |'
	echo '|============================================|'
	make -j"$(nproc)" Image
}

mk_dtbs() {
	echo '|============================================|'
	echo '|             Build device tree              |'
	echo '|============================================|'
	make -j"$(nproc)" dtbs
}

mk_full_image() {
	kernel_setup
	configure_kernel
	echo '|============================================|'
	echo '|          Build IMAGE ARM64 RENESAS         |'
	echo '|============================================|'
	make -j"$(nproc)" Image
	echo '|============================================|'
	echo '|             Build device tree              |'
	echo '|============================================|'
	make -j"$(nproc)" dtbs
}

mk_clean() {
	make clean
}

mk_distclean() {
	make distclean
}

mk_defconfig() {
	kernel_setup
	configure_kernel
}

mk_menuconfig() {
	kernel_setup
	make menuconfig
}

mk_modules() {
	kernel_setup
	configure_kernel
	mk_full_image
	echo '|============================================|'
	echo '|               Build modules                |'
	echo '|============================================|'
	make -j"$(nproc)" modules
	echo "Build completed successfully"
}

mk_modules_install() {
	if [ -z "${KERNEL_MODULES_OUTPUT_DIR:-}" ]; then
		echo "KERNEL_MODULES_OUTPUT_DIR is not set in config.ini."
		echo "Please recheck your setup"
		exit 1
	fi

	mk_modules
	echo '|============================================|'
	echo '|              Install modules               |'
	echo '|============================================|'
	mkdir -p "${KERNEL_MODULES_OUTPUT_DIR}"
	make INSTALL_MOD_PATH="${KERNEL_MODULES_OUTPUT_DIR}" modules_install
	rm -f "${KERNEL_MODULES_OUTPUT_DIR}"/lib/modules/*/build
	echo "Installed kernel modules to ${KERNEL_MODULES_OUTPUT_DIR}"
}

# Main Linux Kernel build
echo "Starting the kernel build at ${KERNEL_DIR}"
cd "${KERNEL_DIR}" || exit 1

case ${1} in
	'clean')
		mk_clean
		;;
	'distclean')
		mk_distclean
		;;
	'defconfig')
		mk_defconfig
		;;
	'menuconfig')
		mk_menuconfig
		;;
	'image')
		mk_defconfig
		mk_image
		;;
	'dtbs')
		mk_defconfig
		mk_dtbs
		;;
	'all')
		mk_modules_install
		;;
	'modules')
		mk_modules
		;;
	'modules-install')
		mk_modules_install
		;;
	*)
		show_help
		;;
esac

exit 0
