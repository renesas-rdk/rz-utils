#!/bin/bash

source ./config.ini
source ./common.sh

# ARCH/CROSS_COMPILE already exported by common.sh; add the extra hardening
# flags/tools main_build.sh wants on top of that.
export KERNEL_CROSS_COMPILE=${CROSS_COMPILE}
export OECORE_TUNE_CCARGS=" -mcpu=cortex-a55+crypto -mbranch-protection=standard"
export CC="aarch64-linux-gnu-gcc  -mcpu=cortex-a55+crypto -mbranch-protection=standard -fstack-protector-strong  -O2 -D_FORTIFY_SOURCE=2 -Wformat -Wformat-security -Werror=format-security"
export CXX="aarch64-linux-gnu-g++  -mcpu=cortex-a55+crypto -mbranch-protection=standard -fstack-protector-strong  -O2 -D_FORTIFY_SOURCE=2 -Wformat -Wformat-security -Werror=format-security"
export CPP="aarch64-linux-gnu-gcc -E  -mcpu=cortex-a55+crypto -mbranch-protection=standard -fstack-protector-strong  -O2 -D_FORTIFY_SOURCE=2 -Wformat -Wformat-security -Werror=format-security"
export LD="aarch64-linux-gnu-ld"
export AS="aarch64-linux-gnu-as"

# Allow PLATFORM override via positional arg
if [ -n "${PLAT:-}" ]; then
	PLATFORM="$PLAT"
	export PLATFORM
fi

# Main process
echo "Starting the build script at $(pwd)"
echo "Target platform ${PLATFORM}"
echo "Using cross toolchain prefix: ${CROSS_COMPILE}"
if [ -z "${1}" ] ; then
	show_help
else
	if [ -z "${2-}" ]; then
		if [ "${1}" = "build-all" ] || [ "${1}" = "clean-all" ]; then
			case ${1} in
				"build-all")
					./build_kernel.sh "all"
					./build_uboot.sh "all"
					./build_atf.sh "all"
					./build_firmware_pack.sh "all"
					./build_flash_writer.sh "all"
					;;
				"clean-all")
					./build_kernel.sh "distclean"
					./build_uboot.sh "distclean"
					./build_atf.sh "distclean"
					# build_firmware_pack.sh has no clean sub_command of its own
					# (its output is just copied/objcopy'd binaries, no build state
					# to distclean) -- remove its output dir directly instead.
					rm -rf "${FIRMWARE_PACK_OUTPUT_DIR}"
					./build_flash_writer.sh "clean"
					;;
				*)
					show_help
					;;
			esac
		else
			show_help
		fi
	else
		if [ "${1}" = "kernel" ] || [ "${1}" = "uboot" ] || [ "${1}" = "atf" ] || [ "${1}" = "firmware-pack" ] || [ "${1}" = "flash-writer" ]; then
			case ${1} in
				"kernel")
					./build_kernel.sh "${2}"
					;;
				"uboot")
					./build_uboot.sh "${2}"
					;;
				"atf")
					./build_atf.sh "${2}"
					;;
				"firmware-pack")
					./build_firmware_pack.sh "${2}"
					;;
				"flash-writer")
					./build_flash_writer.sh "${2}"
					;;
				*)
					show_help
					;;
			esac
		else
			show_help
		fi
	fi
fi

exit 0
