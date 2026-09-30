#!/bin/bash

source ./config.ini
source ./common.sh

# Allow PLATFORM override via positional arg
if [ -n "${PLAT:-}" ]; then
	PLATFORM="$PLAT"
	export PLATFORM
fi

# Kernel only
build_kernel_step() {
	(
		export KERNEL_CROSS_COMPILE="${CROSS_COMPILE}"
		export OECORE_TUNE_CCARGS=" -mcpu=cortex-a55+crypto -mbranch-protection=standard"
		export CC="aarch64-linux-gnu-gcc  -mcpu=cortex-a55+crypto -mbranch-protection=standard -fstack-protector-strong  -O2 -D_FORTIFY_SOURCE=2 -Wformat -Wformat-security -Werror=format-security"
		export CXX="aarch64-linux-gnu-g++  -mcpu=cortex-a55+crypto -mbranch-protection=standard -fstack-protector-strong  -O2 -D_FORTIFY_SOURCE=2 -Wformat -Wformat-security -Werror=format-security"
		export CPP="aarch64-linux-gnu-gcc -E  -mcpu=cortex-a55+crypto -mbranch-protection=standard -fstack-protector-strong  -O2 -D_FORTIFY_SOURCE=2 -Wformat -Wformat-security -Werror=format-security"
		export LD="aarch64-linux-gnu-ld"
		export AS="aarch64-linux-gnu-as"
		./build_kernel.sh "$1"
	)
}

# Main process
echo "Starting the build script at $(pwd)"
echo "Target platform ${PLATFORM}"
echo "Using cross toolchain prefix: ${CROSS_COMPILE}"
case "${1-}" in
	"all")
		./build_flash_writer.sh "all" || exit 1
		./build_atf.sh "all" || exit 1
		./build_uboot.sh "all" || exit 1
		./build_firmware_pack.sh "all" || exit 1
		build_kernel_step "clean" || exit 1
		build_kernel_step "all" || exit 1
		./kernel-modules/kernel_modules_all.sh "clean" || exit 1
		./kernel-modules/kernel_modules_all.sh "all" || exit 1
		;;
	"clean")
		build_kernel_step "distclean" || exit 1
		./build_uboot.sh "distclean" || exit 1
		./build_atf.sh "distclean" || exit 1
		# build_firmware_pack.sh has no clean sub_command
		rm -rf "${FIRMWARE_PACK_OUTPUT_DIR}"
		./build_flash_writer.sh "clean" || exit 1
		./kernel-modules/kernel_modules_all.sh "clean" || exit 1
		;;
	*)
		show_help
		;;
esac

exit 0
