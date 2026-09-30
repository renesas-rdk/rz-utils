#!/bin/bash

# Default cross-compile vars so build_<target>.sh also works standalone.
export ARCH="${ARCH:-arm64}"
export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"

# Clone <repo>@<branch> into <dir> if missing; no-op if already a git repo (never pulls/resets).
ensure_src_dir() {
	local dir="$1" repo="$2" branch="$3" label="$4"

	if [ -d "${dir}/.git" ]; then
		return 0
	fi

	if [ -e "${dir}" ]; then
		echo "Error: ${dir} exists but is not a git repository (no .git found)." >&2
		echo "Refusing to auto-clone ${label} into it -- please check/remove this directory manually." >&2
		exit 1
	fi

	if [ -z "${repo}" ] || [ -z "${branch}" ]; then
		echo "There is no ${label} source at ${dir}, and no repo/branch configured in config.ini to clone it automatically." >&2
		echo "Please clone it manually, or set the matching *_REPO/*_BRANCH variables in config.ini." >&2
		exit 1
	fi

	echo "${label} source not found at ${dir}, cloning ${repo} (branch ${branch})..."
	git clone --branch "${branch}" "${repo}" "${dir}"
}

# Like ensure_src_dir() but pins to a commit; sets SRC_JUST_SYNCED=1 if it actually synced.
ensure_src_dir_at_rev() {
	local dir="$1" repo="$2" rev="$3" label="$4"
	local have just_cloned=0
	SRC_JUST_SYNCED=0

	if [ -z "${repo}" ] || [ -z "${rev}" ]; then
		echo "There is no ${label} source at ${dir}, and no repo/rev configured in config.ini to clone it automatically." >&2
		echo "Please clone it manually, or set the matching *_REPO/*_SRCREV variables in config.ini." >&2
		exit 1
	fi

	if [ ! -d "${dir}/.git" ]; then
		if [ -e "${dir}" ]; then
			echo "Error: ${dir} exists but is not a git repository (no .git found)." >&2
			echo "Refusing to auto-clone ${label} into it -- please check/remove this directory manually." >&2
			exit 1
		fi
		echo "${label} source not found at ${dir}, cloning ${repo}..."
		git clone -q "${repo}" "${dir}"
		just_cloned=1
	fi

	# Repo URL changed since last clone (e.g. fork move) -- repoint origin instead of erroring.
	local origin_url
	origin_url="$(git -C "${dir}" remote get-url origin 2>/dev/null)"
	if [ -n "${origin_url}" ] && [ "${origin_url}" != "${repo}" ]; then
		echo "${label}: origin was ${origin_url}, repointing to ${repo}"
		git -C "${dir}" remote set-url origin "${repo}"
		git -C "${dir}" fetch -q origin
	fi

	have="$(git -C "${dir}" rev-parse HEAD 2>/dev/null)"
	if [ "${have}" = "${rev}" ]; then
		echo "${label}: already at ${rev}"
		# A clone landing exactly on ${rev} skips the checkout below, so flag it here too.
		[ "${just_cloned}" = "1" ] && SRC_JUST_SYNCED=1
		return 0
	fi

	if ! git -C "${dir}" cat-file -e "${rev}^{commit}" 2>/dev/null; then
		git -C "${dir}" fetch -q --all --tags
	fi
	echo "${label}: checking out ${rev}"
	git -C "${dir}" checkout -q -f "${rev}"
	SRC_JUST_SYNCED=1
}

# Apply <patch_dir>/series (filenames, one per line) onto <src_dir> with patch -p1; no-op if missing.
apply_series_patches() {
	local patch_dir="$1" src_dir="$2" label="$3"
	local series="${patch_dir}/series"
	local p

	[ -f "${series}" ] || return 0

	while read -r p; do
		[ -z "${p}" ] && continue
		case "${p}" in \#*) continue;; esac
		echo "${label}: applying ${p}"
		patch -p1 -d "${src_dir}" --no-backup-if-mismatch -i "${patch_dir}/${p}" || {
			echo "Error: failed to apply ${label} patch ${p}" >&2
			exit 1
		}
	done < "${series}"
}

# Reset <dir> to a pristine checkout (no re-clone) and flag SRC_JUST_SYNCED=1 to reapply patches.
clean_repo() {
	local dir="$1" label="$2"

	if [ ! -d "${dir}/.git" ]; then
		echo "Error: ${dir} is not a git repository (no .git found) -- nothing to clean." >&2
		exit 1
	fi

	echo "${label}: resetting to a clean checkout of $(git -C "${dir}" rev-parse --short HEAD)"
	git -C "${dir}" reset -q
	git -C "${dir}" checkout -q .
	git -C "${dir}" clean -q -fdx
	SRC_JUST_SYNCED=1
}

_usage="
Usage:
./main_build.sh all
	Build for all software stacks (Linux Kernel, U-Boot, ATF, Firmware-Pack,
	Flash-Writer, kernel modules)

./main_build.sh clean
	Clean for all software stacks (Linux Kernel, U-Boot, ATF, Firmware-Pack,
	Flash-Writer, kernel modules)

Note: Before executing the build, please make sure updated file config.ini.
"
# Help message
show_help() {
        echo 'Error: Invalid parameter!'
        echo "${_usage}"
        exit 1
}
