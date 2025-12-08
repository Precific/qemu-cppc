## Build scripts for Manjaro

The same steps apply on first installation and on updates of the respective system packages. QEMU must be rebuilt to match the updated qemu-system-x86 package version, KVM after each kernel update.

### Building patched QEMU
Builds `qemu-system-x86_64` with patches applied. These steps should also work on upstream Arch Linux.

In essence:
```bash
./download-sources-qemu.sh
./build-qemu.sh
sudo ./install-qemu.sh
```

Note: the package part of the build-qemu step will show an error at the end, since the PKGBUILD is partially (but not fully) patched to only build the x86_64 targets. The build-qemu script will output if the build process succeeded below that error message.

In the virtual machine configuration, set the emulator path as instructed by the install script.

Note: In Win10 guest configurations, the patched QEMU expects the patched KVM drivers to be loaded (but the patched KVM drivers remain compatible with unpatched QEMU).

### Building patched KVM

Builds the KVM drivers for the current kernel version (optional for Win11 guests). This is based on the Manjaro kernel source repositories.

To build and install (make sure to stop all KVM VMs on your system before installing):
```bash
./download-sources-kvm.sh
./build-kvm.sh
# Note: install-kvm.sh also calls depmod and regenerates initramfs
sudo ./install-kvm.sh
```