#!/bin/bash
# Downloads the sources for QEMU.
# Optional second argument: '-y' to overwrite existing qemu-arch-package subdirectory
set -e
source version-qemu.sh
source util.sh

if [ -d qemu-arch-package ]; then
	echo "Deleting existing qemu-arch-package"
	ask_continue_or_exit
	rm -rf qemu-arch-package
fi

if [ ! -d qemu-arch-package ]; then
	git clone https://gitlab.archlinux.org/archlinux/packaging/packages/qemu qemu-arch-package
fi
pushd qemu-arch-package
git pull
git checkout tags/$QEMUVER_PKG

git apply ../qemu-arch_PKGBUILD_only-x86_64.diff || (echo "FAILED to apply PKGBUILD patch. This will likely build ALL QEMU targets."; sleep 2)

echo "====== Importing and trusting keys in temporary home ======"

tempGNUPGHOME=$(pwd)/.gnupg
mkdir "$tempGNUPGHOME"
TRUSTKEYS=()
for KEYFILE in keys/pgp/*.asc; do
	GNUPGHOME="$tempGNUPGHOME" gpg --import "$KEYFILE"
	#awk for extracting fingerprint based on Stéphane Chazelas https://unix.stackexchange.com/a/743986
	TRUSTKEYS+=($(GNUPGHOME="$tempGNUPGHOME" gpg --with-colons --show-keys "$KEYFILE" | awk -F: '$1 == "pub" {ismain=1}; $1 == "sub" {ismain=0}; ($1 == "fpr" || $1 == "fp2") && ismain {print $10}'))	
done
echo "Creating local private key"
GNUPGHOME="$tempGNUPGHOME" gpg --batch --passphrase '' --quick-gen-key "QEMU Builder" default default 30d
for TRUSTKEY in "${TRUSTKEYS[@]}"; do
	echo "Trusting key $TRUSTKEY"
	GNUPGHOME="$tempGNUPGHOME" gpg --quick-lsign-key "$TRUSTKEY"
done

echo "====== Downloading and preparing QEMU sources ======"
echo "This may take a while as makepkg lints the PKGBUILD"

GNUPGHOME="$tempGNUPGHOME" makepkg --nobuild
popd
