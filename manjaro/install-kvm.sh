#!/bin/bash
set -e
# Optional argument: '-y' to not ask before unloading KVM
source version.sh
source util.sh

if [ $AUTOYES -eq 0 ]; then
	echo "This will unload the KVM kernel modules."
	ask_continue_or_exit
fi

modprobe -r kvm_intel || :
modprobe -r kvm_amd || :
modprobe -r kvm || :

#https://wiki.archlinux.org/title/Kernel_module_package_guidelines
#If a package includes a kernel module that is meant to override an existing module of the same name, such module should be placed in the /lib/modules/X.Y.Z-arch1-1/updates directory. When depmod is run, modules in this directory will take precedence. 

REPLACE_MAINLINE_MODULEFILE=0

if [ $REPLACE_MAINLINE_MODULEFILE -eq 0 ]; then
	mkdir -p /usr/lib/modules/${KERNELVER}/updates
	cp kernel-manjaro-package-${KERNELVER_BRANCH}/src/linux-${KERNELVER_BRANCH}/arch/x86/kvm/kvm*.ko /usr/lib/modules/${KERNELVER}/updates
else
	pushd /usr/lib/modules/${KERNELVER}/kernel/arch/x86/kvm
	for d in kvm*.ko.zst; do
		mv $d $d.backup || :
	done
	popd

	cp kernel-manjaro-package-${KERNELVER_BRANCH}/src/linux-${KERNELVER_BRANCH}/arch/x86/kvm/kvm*.ko /usr/lib/modules/${KERNELVER}/kernel/arch/x86/kvm
fi

depmod -a

modprobe kvm && echo "Inserted kvm"
modprobe kvm_amd && echo "Inserted kvm_amd" || :
modprobe kvm_intel && echo "Inserted kvm_intel" || :