#!/bin/bash
# Downloads the sources for Linux (containing KVM).
# Optional argument: Manjaro linux kernel package name, e.g. linux66. By default, the package name is built from $KERNELVER_BRANCH (version.sh).
# Optional second argument: '-y' to overwrite existing kernel-manjaro-package-<branch> subdirectory

set -e
source version.sh
source util.sh

##Currently running package:
#KERNELPKG_DEFAULT=$(mhwd-kernel -li | grep "Currently running" | grep -oP '\(\K[^\)]+')
#From package branch
KERNELPKG_DEFAULT=linux${KERNELVER_BRANCH//./}

if [ -d kernel-manjaro-package-${KERNELVER_BRANCH} ]; then
	echo "Deleting existing kernel-manjaro-package-${KERNELVER_BRANCH}"
	ask_continue_or_exit
	rm -rf kernel-manjaro-package-${KERNELVER_BRANCH}
fi

git_get_main_branch () { #Source: David Foster, https://stackoverflow.com/a/67625120
    git branch | cut -c 3- | grep -E '^master$|^main$'
}


KERNELPKG=${1:-$KERNELPKG_DEFAULT}
if [ ! -d kernel-manjaro-package-${KERNELVER_BRANCH} ]; then
	git clone https://gitlab.manjaro.org/packages/core/${KERNELPKG} kernel-manjaro-package-${KERNELVER_BRANCH}
fi
pushd kernel-manjaro-package-${KERNELVER_BRANCH}
KERNEL_MAIN_BRANCH=$(git_get_main_branch)
KERNELVER_COMMITMSG=${KERNELVER%"-MANJARO"} #Remove -MANJARO from the version string to match the commit message format
git checkout $KERNEL_MAIN_BRANCH
git pull

#found_kernelver=1 <=> Found the package for $KERNELVER.
found_kernelver=0
# The [pkg-upd] commit may be followed by other important commits for that kernel version.
# Hence, iterating starting from the latest commit, this script checks out the latest non-[pkg-upd] commit before the selected "[pkg-upd] $KERNELVER_COMMITMSG" commit.
#recenthasmsg_other=1 <=> A more recent commit has a message not matching [pkg-upd].
recenthasmsg_other=0
#commit_to_checkout: The actual commit to checkout.
commit_to_checkout=
for commit in $(git rev-list $KERNEL_MAIN_BRANCH); do
	MSG=$(git log --format=%B -n 1 $commit)
	# Also match kernel version number strings (e.g. "6.6"\.[0-9]+), as the [pkg-upd] portion is missing sometimes.
	if [[ "$MSG" =~ ^\[pkg-upd\] ]] || [[ "$MSG" =~ "${KERNELPKG}"\.[0-9]+ ]]; then
		if [[ "$MSG" == *"$KERNELVER_COMMITMSG"* ]]; then
			found_kernelver=1
			
			if [ $recenthasmsg_other -eq 0 ]; then
				commit_to_checkout=$commit
			fi
			break
		fi
		recenthasmsg_other=0
	else
		recenthasmsg_other=1
		commit_to_checkout=$commit
	fi
done
if [ $found_kernelver -eq 0 ]; then
	echo ERROR: Could not find the selected kernel version in the kernel package repository. >&2
	exit 1
fi
git checkout $commit_to_checkout
#rm -rf "src/linux-${KERNELVER_BRANCH}"
# Downloads the sources, applies Manjaro's patches and config
makepkg --nobuild
popd
