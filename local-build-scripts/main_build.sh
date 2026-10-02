#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.ini"
source "${SCRIPT_DIR}/common.sh"

# ipl <sub_command>: ipl_build/build_ipl.sh with the IPL_* settings of config.ini
run_ipl() {
	local sub="${1:-all}" opts=()

	[ -n "${IPL_FEATURES_FILE:-}" ] && opts+=(-c "${IPL_FEATURES_FILE}")
	[ -n "${IPL_FEATURES:-}" ] && opts+=(-f "${IPL_FEATURES}")
	case "${sub}" in
		'all')   ;;
		'keep')  opts+=(-k) ;;
		'force') opts+=(-F) ;;
		'clean')
			echo "Removing IPL output ${IPL_OUT_DIR} (sources in ${IPL_WORK_DIR} are kept)"
			rm -rf "${IPL_OUT_DIR}"
			return 0
			;;
		*) show_help ;;
	esac

	# shellcheck disable=SC2086
	WORK_DIR="${IPL_WORK_DIR}" OUT_DIR="${IPL_OUT_DIR}" GIT_SHALLOW="${GIT_SHALLOW}" \
		"${SCRIPT_DIR}/ipl_build/build_ipl.sh" "${opts[@]}" ${IPL_BOARDS}
}

# kernel-modules <sub_command> [module]: all modules (kernel_modules_all.sh) or one
run_kernel_modules() {
	local sub="$1" module="${2:-}"

	case "${sub}" in
		'fetch'|'reset-src'|'all'|'install'|'clean') ;;
		*) show_help ;;
	esac
	if [ -n "${module}" ]; then
		[ -x "${SCRIPT_DIR}/kernel-modules/build_${module}.sh" ] || {
			echo "Error: unknown kernel module '${module}' (no kernel-modules/build_${module}.sh)" >&2
			exit 1
		}
		"${SCRIPT_DIR}/kernel-modules/build_${module}.sh" "${sub}"
	else
		"${SCRIPT_DIR}/kernel-modules/kernel_modules_all.sh" "${sub}"
	fi
}

# Main process
echo "Starting the build script at $(pwd)"
echo "Target board: RZ/V2H RDK (IPL: ${IPL_BOARDS})"
echo "Using cross toolchain prefix: ${CROSS_COMPILE}"
if [ -z "${1:-}" ] ; then
	show_help
fi

case ${1} in
	"all")
		[ -z "${2:-}" ] || show_help
		"${SCRIPT_DIR}/build_kernel.sh" "all" || exit 1
		run_kernel_modules "install" || exit 1
		run_ipl "all" || exit 1
		"${SCRIPT_DIR}/deploy.sh" || exit 1
		;;
	"clean-all")
		[ -z "${2:-}" ] || show_help
		"${SCRIPT_DIR}/build_kernel.sh" "distclean"
		run_kernel_modules "clean"
		run_ipl "clean"
		;;
	"kernel")
		[ -n "${2:-}" ] || show_help
		"${SCRIPT_DIR}/build_kernel.sh" "${2}" || exit 1
		;;
	"kernel-modules")
		[ -n "${2:-}" ] || show_help
		run_kernel_modules "${2}" "${3:-}" || exit 1
		;;
	"ipl")
		run_ipl "${2:-all}" || exit 1
		;;
	"deploy")
		[ -z "${2:-}" ] || show_help
		"${SCRIPT_DIR}/deploy.sh" || exit 1
		;;
	*)
		show_help
		;;
esac

exit 0
