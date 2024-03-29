#!/bin/bash
source version.sh

set -e

pushd kernel-manjaro-package-${KERNELVER_BRANCH}
ls src/linux-${KERNELVER_BRANCH}/ 2> /dev/null || makepkg --nobuild
cd src/linux-${KERNELVER_BRANCH}/
patch -Np1 -i ${KVMPATCH} || :
if [ ! -f "/usr/lib/modules/$KERNELVER/build/Module.symvers" ]; then
	echo Missing Module.symvers from the kernel-devel package
	exit 1
fi
[ -L Module.symvers ] && rm Module.symvers
[ -L vmlinux ] && rm vmlinux
ls Module.symvers 2> /dev/null || ln -s /usr/lib/modules/$KERNELVER/build/Module.symvers ./
ls vmlinux 2> /dev/null || ln -s /usr/lib/modules/$KERNELVER/build/vmlinux ./
make -j16 modules_prepare
make -j16 M=arch/x86/kvm modules

popd
