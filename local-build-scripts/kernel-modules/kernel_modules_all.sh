#!/bin/bash
#
# Clean + build + install all 7 out-of-tree kernel modules
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Order matters: vspm before vspm_if.
MODULES=(mmngr mmngrbuf vspm vspm_if mali_kbase uvcs_drv 88x2bu)

declare -A RESULT
FAILED=0

for name in "${MODULES[@]}"; do
	echo
	echo '================================================================'
	echo "  ${name}: ./build_${name}.sh (clean + install)"
	echo '================================================================'
	if "./build_${name}.sh"; then
		RESULT["${name}"]="OK"
	else
		RESULT["${name}"]="FAILED"
		FAILED=1
	fi
done

echo
echo '================================================================'
echo "  Summary (clean + install)"
echo '================================================================'
for name in "${MODULES[@]}"; do
	printf '  %-12s %s\n' "${name}" "${RESULT[${name}]}"
done

exit ${FAILED}
