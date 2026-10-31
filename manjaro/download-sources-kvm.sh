#!/bin/bash
# Downloads the sources for Linux (containing KVM and other relevant modules).
# Optional argument: Manjaro linux kernel package name, e.g. linux66. By default, the package name is built from $KERNELVER_BRANCH (version.sh).
# Optional second argument: '-y' to overwrite existing kernel-manjaro-package-<branch> subdirectory

set -e
source unsets.sh
rm -f .kernelver
source version-kernel.sh
source util.sh

if [ $AUTOYES -ne 1 ] && [ ${PATCHSEL_INTERACTIVE} -ne 1 ]; then
	interactive_patchsel
fi
echo "Patch selection:"
for patchkey in "${patchsel_keys[@]}"; do
	echo "- ${patchkey}=${patchsel[$patchkey]}"
done
echo "----------"

##Currently running package:
#KERNELPKG_DEFAULT=$(mhwd-kernel -li | grep "Currently running" | grep -oP '\(\K[^\)]+')
#From package branch, e.g. linux72
KERNELPKG_DEFAULT=linux${KERNELVER_BRANCH//./}

git_get_main_branch () { #Source: David Foster, https://stackoverflow.com/a/67625120
    git branch | cut -c 3- | grep -E '^master$|^main$'
}


KERNELPKG=${1:-$KERNELPKG_DEFAULT}
if [ ! -d manjaro-pkgbuilds ]; then
    git clone https://code.manjaro.org/packages/PKGBUILDs.git manjaro-pkgbuilds
fi
pushd manjaro-pkgbuilds
KERNEL_MAIN_BRANCH=$(git_get_main_branch)
KERNELVER_COMMITMSG=${KERNELVER%"-MANJARO"} #Remove -MANJARO from the version string to match the commit message format
git checkout $KERNEL_MAIN_BRANCH
git pull

#List of non-[pkg-upd] commits to disregard
KNOWNBROKEN_LIST=""
KNOWNBROKEN_LIST+=" a13b9da9dd7a4d810bfda661e2b269c887e48202" #6.10.0-1 with config 6.10.0-2 and invalid sha256sum

#found_kernelver=1 <=> Found the package for $KERNELVER.
found_kernelver=0
# The "linux72: Update to 7.2.14-1" commit may be followed by other important commits for that kernel version.
# Hence, iterating starting from the latest commit, this script checks out the newest non-"Update to" commit succeeding the selected "[pkg-upd] $KERNELVER_COMMITMSG" commit.
# Note that the iteration order is newest to oldest.
#recenthasmsg_other=1 <=> A more recent commit has a message not matching [pkg-upd].
recenthasmsg_other=0
#commit_to_checkout: The actual commit to checkout.
commit_to_checkout=
for commit in $(git rev-list $KERNEL_MAIN_BRANCH core/${KERNELPKG}); do
	MSG=$(git log --format=%B -n 1 $commit)
	# Also match kernel version number strings (e.g. "6.6"\.[0-9]+), as the [pkg-upd] portion is missing sometimes.
	if [[ "$MSG" =~ ^"${KERNELPKG}: Update to " ]] || [[ "$MSG" =~ "${KERNELVER_BRANCH}"\.[0-9]+ ]]; then
		if [[ "$MSG" == *"$KERNELVER_COMMITMSG"* ]]; then
			found_kernelver=1
			echo "Found kernel version commit $commit ($MSG)"
			
			if [ $recenthasmsg_other -eq 0 ]; then
				commit_to_checkout=$commit
			else
				echo "Choosing newer commit $commit_to_checkout ($(git log --format=%B -n 1 $commit_to_checkout))"
			fi
			break
		fi
		recenthasmsg_other=0
	else
		isbroken=0
		for KNOWNBROKEN in ${KNOWNBROKEN_LIST}; do
			if [ "$commit" == "$KNOWNBROKEN" ]; then
				echo "Ignoring known-broken commit $commit ($MSG)"
				isbroken=1
				break
			fi
		done
		if [ $isbroken -eq 0 ]; then
			recenthasmsg_other=1
			commit_to_checkout=$commit
		fi
	fi
done
if [ $found_kernelver -eq 0 ]; then
	echo "ERROR: Could not find the selected kernel version in the kernel package repository." >&2
	echo "You can try manually checking out the correct commit in manjaro-pkgbuilds/core/${KERNELPKG}. Copy to (overwriting) kernel-manjaro-package-${KERNELVER_BRANCH} and in there, run \'makepkg --nobuild\'." >&2
	exit 1
fi
git checkout $commit_to_checkout
popd

if [ -d kernel-manjaro-package-${KERNELVER_BRANCH} ]; then
	echo "Deleting old kernel-manjaro-package-${KERNELVER_BRANCH}"
	ask_continue_or_exit
	rm -rf "kernel-manjaro-package-${KERNELVER_BRANCH}"
fi
cp -r "manjaro-pkgbuilds/core/${KERNELPKG}" "kernel-manjaro-package-${KERNELVER_BRANCH}"
pushd "kernel-manjaro-package-${KERNELVER_BRANCH}"

shopt -s nullglob
# Look for old kernel sources. Should only happen if the user ran makepkg in manjaro-pkgbuilds.
KERNELSRCDIRS=(src/linux-*/)
if [ ${#KERNELSRCDIRS[@]} -gt 0 ]; then
	echo "Deleting old kernel sources in kernel-manjaro-package-${KERNELVER_BRANCH}/src/linux-*"
	ask_continue_or_exit
	rm -rf "${KERNELSRCDIRS[@]}"
fi

# Downloads the sources, applies Manjaro's patches and config
makepkg --nobuild
popd
