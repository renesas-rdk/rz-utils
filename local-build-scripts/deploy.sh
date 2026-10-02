#!/bin/bash
#
# Collect what has been built (kernel, device trees, modules, IPL) plus uEnv.txt into the
# layout of the board's root filesystem, ready to copy to the board (no .deb):
#
#   DEPLOY_DIR/rzv2h-rdk[-rt]/
#   ├── boot/Image
#   ├── boot/dtb/renesas/rzv2h-rdk-{ver1,ver101}.dtb
#   ├── boot/dtb/renesas/overlays/rzv2h-rdk-*.dtbo
#   ├── boot/uEnv.txt
#   ├── boot/{bl2_bp_esd,fip}-rzv2h-rdk-<ver>.bin     (IPL_BOARDS)
#   ├── usr/lib/modules/<release>/                    (in-tree + extra/ out-of-tree)
#   └── deploy-info.txt
#
# KERNEL_VARIANT picks the flavour: rzv2h-rdk (non-RT) or rzv2h-rdk-rt (preempt-rt). The
# kernel and the modules are deployed only if they were built for that flavour (.config,
# Image and every module's vermagic agree), so RT and non-RT never mix. A part that is not
# built, or not built for this flavour, is skipped with a warning.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.ini"
source "${SCRIPT_DIR}/common.sh"

STRIP="${CROSS_COMPILE}strip"
MARKER="deploy-info.txt"

skip() {
	echo "Skip: $*" >&2
}

flavour() { [ "$1" = 1 ] && echo "RT" || echo "non-RT"; }

want_rt=0
[ "${KERNEL_VARIANT:-}" = "preempt-rt" ] && want_rt=1
name="rzv2h-rdk$([ "${want_rt}" = 1 ] && echo -rt)"
DEST="${DEPLOY_DIR}/${name}"
echo "Deploying the $(flavour ${want_rt}) kernel (KERNEL_VARIANT=${KERNEL_VARIANT:-}) to ${DEST}"

# ---- What can be deployed --------------------------------------------------------------

# Kernel build output: KBUILD_OUTPUT if the kernel was built out of tree, else KERNEL_DIR
KBUILD="${KBUILD_OUTPUT:-${KERNEL_DIR}}"
IMAGE="${KBUILD}/arch/arm64/boot/Image"
DTS="${KBUILD}/arch/arm64/boot/dts/renesas"

# Kernel: Image built, for the wanted flavour, and the Image matches .config
release="" banner="" kernel_ok=0
if [ ! -f "${KBUILD}/.config" ] || [ ! -f "${IMAGE}" ]; then
	skip "kernel: not built in ${KBUILD}"
else
	release="$(make -s -C "${KBUILD}" LOCALVERSION= kernelrelease 2>/dev/null | tail -1)"
	banner="$(strings "${IMAGE}" | grep -m1 '^Linux version ')"
	config_rt=0
	grep -q '^CONFIG_PREEMPT_RT=y' "${KBUILD}/.config" && config_rt=1
	image_rt=0
	case "${banner}" in *PREEMPT_RT*) image_rt=1 ;; esac

	if [ -z "${release}" ]; then
		skip "kernel: cannot read the kernel release from ${KBUILD}"
	elif [ "${config_rt}" != "${want_rt}" ]; then
		skip "kernel: ${KBUILD} holds a $(flavour ${config_rt}) kernel (${release}), not $(flavour ${want_rt})"
	elif [ "${image_rt}" != "${config_rt}" ] || [ "${banner#"Linux version ${release} "}" = "${banner}" ]; then
		skip "kernel: ${IMAGE} (\"${banner}\") does not match .config (${release}); rebuild it"
	else
		kernel_ok=1
		echo "Kernel:  ${release} from ${KBUILD}"
	fi
fi

# Modules of that release only, and every one built for it
MODSRC="" modules_ok=0
if [ "${kernel_ok}" = 1 ]; then
	MODSRC="${KERNEL_MODULES_OUTPUT_DIR}/lib/modules/${release}"
	if [ ! -d "${MODSRC}/kernel" ]; then
		skip "modules: none for ${release} in ${MODSRC}"
	else
		want_magic="${release} SMP $([ "${want_rt}" = 1 ] && echo preempt_rt || echo preempt) "
		bad=0
		while IFS= read -r -d '' ko; do
			magic="$(modinfo -F vermagic "${ko}" 2>/dev/null)"
			case "${magic}" in
				"${want_magic}"*) ;;
				*) echo "  ${ko#"${MODSRC}"/}: vermagic \"${magic}\"" >&2; bad=1 ;;
			esac
		done < <(find "${MODSRC}" -name '*.ko' -print0)
		if [ "${bad}" = 1 ]; then
			skip "modules: the ones above were not built for ${release}; rebuild them"
		else
			modules_ok=1
			for m in mmngr mmngrbuf vspm vspm_if mali_kbase uvcs_drv; do
				[ -f "${MODSRC}/extra/${m}.ko" ] ||
					skip "modules: ${m}.ko not built (./main_build.sh kernel-modules install)"
			done
		fi
	fi
else
	skip "modules: they go with the kernel"
fi

# IPL of each board in IPL_BOARDS
ipl_boards=""
for board in ${IPL_BOARDS}; do
	out="${IPL_OUT_DIR}/rzv2h-rdk-${board}"
	if [ -f "${out}/bl2_bp_esd-rzv2h-rdk-${board}.bin" ] && [ -f "${out}/fip-rzv2h-rdk-${board}.bin" ]; then
		ipl_boards="${ipl_boards} ${board}"
	else
		skip "IPL ${board}: not built in ${out}"
	fi
done
ipl_boards="${ipl_boards# }"

if [ "${kernel_ok}" = 0 ] && [ -z "${ipl_boards}" ]; then
	echo "Error: nothing built to deploy" >&2
	exit 1
fi

# ---- Deploy ------------------------------------------------------------------------------

# Recreated on every run, so it only ever holds what is built now
if [ -e "${DEST}" ]; then
	if [ ! -f "${DEST}/${MARKER}" ]; then
		echo "Error: ${DEST} exists and was not made by deploy.sh; remove it yourself" >&2
		exit 1
	fi
	rm -rf "${DEST}"
fi
install -d "${DEST}/boot" || exit 1
install -m 644 "${SCRIPT_DIR}/ipl_build/uEnv.txt" "${DEST}/boot/uEnv.txt" || exit 1

if [ "${kernel_ok}" = 1 ]; then
	install -d "${DEST}/boot/dtb/renesas/overlays" || exit 1
	install -m 644 "${IMAGE}" "${DEST}/boot/Image" || exit 1
	install -m 644 "${DTS}"/rzv2h-rdk-ver*.dtb "${DEST}/boot/dtb/renesas/" || exit 1
	install -m 644 "${DTS}"/overlays/rzv2h-rdk-*.dtbo "${DEST}/boot/dtb/renesas/overlays/" || exit 1
fi

if [ "${modules_ok}" = 1 ]; then
	install -d "${DEST}/usr/lib/modules" || exit 1
	cp -a "${MODSRC}" "${DEST}/usr/lib/modules/" || exit 1
	rm -f "${DEST}/usr/lib/modules/${release}/build" "${DEST}/usr/lib/modules/${release}/source"
	# Same as the kernel .deb: debug info is not needed on the board
	if [ "${DEPLOY_STRIP:-1}" = 1 ]; then
		find "${DEST}/usr/lib/modules/${release}" -name '*.ko' -exec "${STRIP}" --strip-debug {} + || exit 1
	fi
fi

for board in ${ipl_boards}; do
	out="${IPL_OUT_DIR}/rzv2h-rdk-${board}"
	install -m 644 "${out}/bl2_bp_esd-rzv2h-rdk-${board}.bin" "${out}/fip-rzv2h-rdk-${board}.bin" \
		"${DEST}/boot/" || exit 1
done

kernel_rev="$(git -C "${KERNEL_DIR}" describe --always --dirty 2>/dev/null)"
cat > "${DEST}/${MARKER}" <<EOF
flavour:        $(flavour ${want_rt})
release:        ${release:-not deployed}
kernel source:  ${KERNEL_DIR} (${kernel_rev:-unknown})
kernel build:   ${KBUILD}
Image:          ${banner:-not deployed}
modules:        $([ "${modules_ok}" = 1 ] && echo "${MODSRC}" || echo "not deployed")
IPL boards:     ${ipl_boards:-none}
deployed:       $(date '+%Y-%m-%d %H:%M:%S')
EOF

echo
echo "Deployed to ${DEST}:"
if [ "${kernel_ok}" = 1 ]; then
	echo "  boot/Image (${release}), $(cd "${DEST}/boot/dtb/renesas" && ls *.dtb overlays/*.dtbo | tr '\n' ' ')"
fi
if [ "${modules_ok}" = 1 ]; then
	echo "  usr/lib/modules/${release}: $(find "${DEST}/usr/lib/modules/${release}/kernel" -name '*.ko' | wc -l) in-tree," \
		"extra/: $(ls "${DEST}/usr/lib/modules/${release}/extra" 2>/dev/null | tr '\n' ' ')"
fi
echo "  boot/uEnv.txt, IPL: ${ipl_boards:-none}"
echo
echo "To the board (then reboot; the IPL files are for flashing, see ipl_build/README.md):"
echo "  rsync -a --exclude ${MARKER} ${DEST}/ root@<board>:/"
