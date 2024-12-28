#!/bin/bash
set -e
# Optional argument: '-y' to not ask before unloading KVM
source version-kernel.sh
source util.sh

shopt -s nullglob

SRCSUBDIRS=(kernel-manjaro-package-${KERNELVER_BRANCH}/src/linux-*/)
if [ ${#SRCSUBDIRS[@]} -ne 1 ]; then
	echo "Unable to find the linux source directory"
	exit 1
fi
SRCSUBDIR="${SRCSUBDIRS[0]::-1}"

MODULES_UPDATE=("${SRCSUBDIR}/arch/x86/kvm/"kvm*.ko)
MODULES_REPLACE=()

NEEDS_RELOAD_VFIOPCI=0
if [ -f "${SRCSUBDIR}/drivers/vfio/pci/vfio-pci-core.ko" ]; then
	#MODULES_REPLACE+=("drivers/vfio/pci/vfio-pci-core.ko")
	MODULES_UPDATE+=("${SRCSUBDIR}/drivers/vfio/pci/vfio-pci-core.ko")
	NEEDS_RELOAD_VFIOPCI=1
fi

RELOAD_MODULES=1
if [ "$KERNELVER" != "$(uname -r)" ]; then
	RELOAD_MODULES=0
fi
if [ $RELOAD_MODULES -eq 1 ]; then
	if [ $AUTOYES -eq 0 ]; then
		echo "This will unload the KVM kernel modules."
		ask_continue_or_exit
	fi

	modprobe -r kvm_intel || :
	modprobe -r kvm_amd || :
	modprobe -r kvm || :
fi

#https://wiki.archlinux.org/title/Kernel_module_package_guidelines
#If a package includes a kernel module that is meant to override an existing module of the same name, such module should be placed in the /lib/modules/X.Y.Z-arch1-1/updates directory. When depmod is run, modules in this directory will take precedence. 
if [ ${#MODULES_UPDATE[@]} -gt 0 ]; then
	mkdir -p /usr/lib/modules/${KERNELVER}/updates
	cp "${MODULES_UPDATE[@]}" /usr/lib/modules/${KERNELVER}/updates
fi

for MODULE_REPLACE in "${MODULES_REPLACE[@]}"; do
	in="${SRCSUBDIR}/${MODULE_REPLACE}"
	out="/usr/lib/modules/${KERNELVER}/kernel/${MODULE_REPLACE}"
	#Shouldn't overwrite the original module, since ours isn't compressed and doesn't have the .zst ending.
	for out_existing in "${out}"*; do
		mv -f "${out_existing}" "$(dirname "${out_existing}")/$(basename "${out_existing}").bak"
	done
	cp "${in}" "${out}"
done

depmod -a "${KERNELVER}"
echo "Regenerating initramfs."
mkinitcpio -p "$MKINITCPIO_NAME" || :

if [ $RELOAD_MODULES -eq 1 ]; then
	modprobe kvm && echo "Inserted kvm"
	modprobe kvm_amd && echo "Inserted kvm_amd" || :
	modprobe kvm_intel && echo "Inserted kvm_intel" || :
	if [ $NEEDS_RELOAD_VFIOPCI -eq 1 ]; then
		# We can't reliably yank off the driver.
		# If a device is currently bound to vfio-pci (which requires vfio-pci-core), it needs to be detached first.
		echo "Note: vfio-pci-core needs to be reloaded, e.g. by a reboot."
	fi
fi