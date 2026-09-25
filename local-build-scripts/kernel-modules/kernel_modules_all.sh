#!/bin/bash
#
# Build/install/clean all 7 out-of-tree kernel modules in dependency order (vspm before vspm_if).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

cmd="${1:-all}"

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

exit ${FAILED}
