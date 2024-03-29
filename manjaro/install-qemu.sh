#!/bin/bash
set -e

QEMUOUTDIR=$(pwd)/bin-qemu-cppc
INSTALLPATH=$(which qemu-system-x86_64)-cppc

sudo cp "$QEMUOUTDIR/qemu-system-x86_64" "$INSTALLPATH"
sudo chmod +x "$INSTALLPATH"

echo "Installed the patched qemu binary to '$INSTALLPATH'."
echo "In the libvirt domain xml, add <emulator>$INSTALLPATH</emulator> to devices."