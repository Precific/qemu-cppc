#!/bin/bash
source unsets.sh
source version-kernel.sh

set -e
shopt -s nullglob

pushd kernel-manjaro-package-${KERNELVER_BRANCH}
SRCSUBDIRS=(src/linux-*/)
[ ${#SRCSUBDIRS[@]} -ge 1 ] || makepkg --nobuild
SRCSUBDIRS=(src/linux-*/)
if [ ${#SRCSUBDIRS[@]} -lt 1 ]; then
        echo "ERROR: Cannot find the extracted linux source directory in kernel-manjaro-package-${KERNELVER_BRANCH}/src" >&2
        exit 1
elif [ ${#SRCSUBDIRS[@]} -gt 1 ]; then
        echo "ERROR: Found several extracted linux source directories in kernel-manjaro-package-${KERNELVER_BRANCH}/src" >&2
        exit 1
fi
SRCSUBDIR=${SRCSUBDIRS[0]}
cd ${SRCSUBDIR}

BUILD_VFIOPCICORE=0
if [ "${KVMPATCH_CPPC}" != "" ] && [ ${patchsel[KVMCPPC]:-0} -eq 1 ]; then
	echo "Applying CPPC KVM patch"
	patch -Np1 -i "${KVMPATCH_CPPC}"
fi
if [ "${KVMPATCH_REGRESSION_612}" != "" ] && [ ${patchsel[KVMREGRESSION612]:-0} -eq 1 ]; then
	echo "Applying 6.12 AMD KVM regression patch"
	patch -Np1 -i "${KVMPATCH_REGRESSION_612}"
fi
if [ "${VFIOPCICORE_REGRESSION_612}" != "" ] && [ ${patchsel[VFIOPCIREGRESSION612]:-0} -eq 1 ]; then
	echo "Applying 6.12 vfio-pci-core regression patch"
	patch -Np1 -i "${VFIOPCICORE_REGRESSION_612}"
	BUILD_VFIOPCICORE=1
fi
if [ ! -f "/usr/lib/modules/$KERNELVER/build/Module.symvers" ]; then
	echo "ERROR: Missing Module.symvers from the kernel-devel package" >&2
	exit 1
fi

echo "Building kernel modules"
[ -L Module.symvers ] && rm Module.symvers
[ -L vmlinux ] && rm vmlinux
ls Module.symvers 2> /dev/null || ln -s /usr/lib/modules/$KERNELVER/build/Module.symvers ./
ls vmlinux 2> /dev/null || ln -s /usr/lib/modules/$KERNELVER/build/vmlinux ./
make LOCALVERSION= -j16 modules_prepare
make LOCALVERSION= M=arch/x86/kvm -j16 modules
if [ ${BUILD_VFIOPCICORE} -eq 1 ]; then
	make LOCALVERSION= M=drivers/vfio/pci -j16 modules
fi

popd
