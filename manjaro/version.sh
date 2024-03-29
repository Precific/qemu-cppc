#!/bin/bash

#KERNELVER=6.6.19-1-MANJARO
KERNELVER=$(uname -r)

#KERNELVER_BRANCH=6.6
KERNELVER_BRANCH=$(echo "$KERNELVER" | grep -oP '^[0-9]+\.[0-9]+')
#LINUXVER=linux-6.6
LINUXVER=linux-${KERNELVER_BRANCH}

KVMPATCH=$(pwd)/../linux-${KERNELVER_BRANCH}-kvm-cppc.patch
#-> Additional logic for patch file choice may be needed if compatibility breaks between minor kernel releases.

#QEMUVER=qemu-8.2.2
QEMUVER=qemu-$(qemu-system-x86_64 -version | grep "QEMU emulator version" | grep -oP 'version \K.+')
#QEMUVER_PKG=8.2.2-1
QEMUVER_PKG=$(pacman -Q qemu-system-x86 | grep -oP ' \K[^ ]+')
#QEMUVER_BRANCHVER=8.2
QEMUVER_BRANCHVER=$(echo "$QEMUVER_PKG" | grep -oP '^[0-9]+\.[0-9]+')

QEMUPATCH=$(pwd)/../qemu-${QEMUVER_BRANCHVER}.0-cppc.patch
#-> Additional logic for patch file choice may be needed if compatibility breaks between minor QEMU releases.