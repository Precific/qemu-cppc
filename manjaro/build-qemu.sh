#!/bin/bash
set -e
source version.sh

QEMUOUTDIR=$(pwd)/bin-qemu-cppc
rm -rf "$QEMUOUTDIR"

pushd qemu-arch-package
rm -rf src/qemu-*/
rm -rf src/build
rm -rf pkg

GNUPGHOME="$(pwd)/.gnupg" makepkg -c --nobuild
patch -Np1 -d src/qemu-*/ -i ${QEMUPATCH}
GNUPGHOME="$(pwd)/.gnupg" makepkg -f --noextract || :

QEMUFILE=src/build/qemu-system-x86_64
if [ -f pkg/qemu-system-x86/usr/bin/qemu-system-x86_64 ]; then
	QEMUFILE=pkg/qemu-system-x86/usr/bin/qemu-system-x86_64
fi
if [ ! -f "$QEMUFILE" ] || [[ -z $(file "$QEMUFILE" 2>/dev/null | grep executable || :) ]]; then
	echo "FAILURE: qemu-system-x86_64 build output not found"
	exit 1
fi
echo "SUCCESS: Built qemu-system-x86_64"

mkdir -p "$QEMUOUTDIR"
cp "$QEMUFILE" "$QEMUOUTDIR/"

popd
