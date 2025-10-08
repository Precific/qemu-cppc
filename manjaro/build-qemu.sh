#!/bin/bash
# Optional argument: '-y' to overwrite existing QEMU source directories
set -e

source version-qemu.sh
source util.sh

QEMUOUTDIR=$(pwd)/bin-qemu-cppc
rm -rf "$QEMUOUTDIR"

pushd qemu-arch-package
if [ $AUTOYES -eq 0 ]; then
	echo "This will remove any existing QEMU source directories in the qemu-arch-package subdirectory."
	echo "If you have done any changes to those, make sure to create a backup or a patch file first."
	ask_continue_or_exit
fi

echo "Clearing QEMU sources."
rm -rf src/qemu-*/
rm -rf src/build
rm -rf pkg

echo "Invoking makepkg, this may take a while to start."
GNUPGHOME="$(pwd)/.gnupg" makepkg -c --nobuild
patch -Np1 -d src/qemu-*/ -i ${QEMUPATCH}
echo "Building patched QEMU. Invoking makepkg, this may take a while to start."
GNUPGHOME="$(pwd)/.gnupg" makepkg -f --noextract || :

QEMUFILE=src/build/qemu-system-x86_64
if [ -f pkg/qemu-system-x86/usr/bin/qemu-system-x86_64 ]; then
	QEMUFILE=pkg/qemu-system-x86/usr/bin/qemu-system-x86_64
fi
if [ ! -f "$QEMUFILE" ] || [[ -z $(file "$QEMUFILE" 2>/dev/null | grep executable || :) ]]; then
	echo "FAILURE: qemu-system-x86_64 build output not found"
	exit 1
fi
# Make it green so it stands out against the build 'ERROR' message (caused by skipping some builds)
tput setaf 2 || :; tput setab 0 || :;
echo -n "SUCCESS"
tput sgr0 || :;
echo ": Built qemu-system-x86_64. Errors in package_qemu-common() above can be ignored."

mkdir -p "$QEMUOUTDIR"
cp "$QEMUFILE" "$QEMUOUTDIR/"

echo "Done"

popd
