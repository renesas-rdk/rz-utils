#!/bin/bash
#
# Build/install or clean all 7 out-of-tree kernel modules in dependency order (vspm before vspm_if).
#
# Usage: ./kernel_modules_all.sh {all|clean}

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "${SCRIPT_DIR}/.."
source ./config.ini
source ./common.sh
cd "${SCRIPT_DIR}"

case "${1-}" in
	all|clean) ;;
	*)
		echo "Usage: $0 {all|clean}" >&2
		exit 1
		;;
esac
cmd="${1}"

# Order matters: vspm before vspm_if.
MODULES=(mmngr mmngrbuf vspm vspm_if mali_kbase uvcs_drv 88x2bu)

declare -A RESULT
FAILED=0

for name in "${MODULES[@]}"; do
	echo
	echo '================================================================'
	echo "  ${name}: ./build_${name}.sh ${cmd}"
	echo '================================================================'
	if "./build_${name}.sh" "${cmd}"; then
		RESULT["${name}"]="OK"
	else
		RESULT["${name}"]="FAILED"
		FAILED=1
	fi
done

echo
echo '================================================================'
echo "  Summary (${cmd})"
echo '================================================================'
for name in "${MODULES[@]}"; do
	printf '  %-12s %s\n' "${name}" "${RESULT[${name}]}"
done

# Copy output into RELEASE_OUTPUT_DIR
if [ "${cmd}" = "all" ]; then
	if [ -z "${RELEASE_OUTPUT_DIR:-}" ]; then
		echo "RELEASE_OUTPUT_DIR is not set in config.ini -- skipping release copy." >&2
	elif [ -z "${KERNEL_MODULES_OUTPUT_DIR:-}" ] || [ ! -d "${KERNEL_MODULES_OUTPUT_DIR}/lib" ]; then
		echo "Warning: ${KERNEL_MODULES_OUTPUT_DIR:-KERNEL_MODULES_OUTPUT_DIR}/lib not found -- skipping release copy." >&2
	else
		outdir="${RELEASE_OUTPUT_DIR}/modules"
		mkdir -p "${outdir}"
		cp -r "${KERNEL_MODULES_OUTPUT_DIR}/lib" "${outdir}/"
		echo "Published kernel modules (in-tree + out-of-tree) to ${outdir}/lib/modules/"
	fi
fi

exit ${FAILED}
