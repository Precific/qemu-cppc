## QEMU/KVM: ACPI CPPC patches for Windows guests
(and vfio-related kernel patches)

This repo contains QEMU and KVM patches that enable reporting of per-core performance indicators to x86_64 Windows guests through ACPI CPPC. The goal is to improve overall guest performance especially with heterogeneous CPU designs (Ryzen dual-CCD X3D chips [*tested*], Intel P+E-Core [*not tested*]) but also to expose the per-core 'maximum performance' boost metrics present on recent AMD Ryzen processors. 

Windows uses the CPPC `highest_perf` per-core attributes as hints for thread scheduling. The drivers responsible for these scheduling hints are amdppm.sys [*tested*], intelppm.sys [*not tested*] or the generic processr.sys [*not tested but likely to work*]. In practice, if a program loads 8 threads, Windows 10 will usually schedule those onto the 8 fastest cores by `highest_perf`, while background tasks are moved to the slowest cores. Windows 11 is less consistent but also tends to load the 'fastest' core first. Energy profiles likely alter this behavior.

**Disclaimer**: These patches should not be considered suitable for productive use and may open up a minor side-channel to the guest OS (exposing a host performance counter) if the guest cores are not isolated from the host. Windows 10 needs an additional hacky workaround. While I have not encountered any issues with the W10 workaround, your mileage may vary.

The patches may break nested virtualization / virtualization-based security in Windows 10 guest systems. Windows 11 24H2 CPPC functionality has only been tested without nested virtualization.

## Usage
- The relevant patch files are in the root directory of this repo. There also are build and install instructions for Manjaro (Arch-based) in the [manjaro](manjaro) subdirectory.
- Install the patched `kvm`, `kvm_amd`, `kvm_intel` kernel modules and `qemu-system-x86_64-cppc` application. 
- Format the mapping from guest to host threads (`<vCPU>:<host_thread#>`) as a list separated by comma characters.
  
  For instance, in the libvirt domain configuration,
  ```xml
  <vcpupin vcpu="0" cpuset="4"/>
  <vcpupin vcpu="1" cpuset="20"/>
  ```
  turns into `0:4,1:20` without spaces.

  With QEMU on i386/x86_64, note that the virtual SMT/HT threads (from the topology configuration) are always assigned consecutive `vcpu` IDs, which can differ from the ordering of host threads. This needs to be accounted for not only to avoid general performance and security penalties, but also for the guest OS to not reject CPPC.
- Call the `mkparams_cppc_device.py` script to generate a QEMU command line (either plain, or as libvirt xml). Follow the script's usage notes.

  Example for a Ryzen 7950X3D with (optional) offsets to prefer the V-Cache cores (host threads 0..7 and 16..23) over the high-frequency cores:
  ```bash
  python mkparams_cppc_device.py config_libvirt --smt 2 --offset_highestperf 0..7=+40,8..15=-40,16..23=+40,24..31=-40 --vcpu_assignment 0:4,1:20,<etc. for all 32 threads>
  ```
    Note: The highest_perf numbers should remain in [0..255] with the offsets applied.

- To add the QEMU command-line to the libvirt XML, change the root domain XML node to `<domain xmlns:qemu="http://libvirt.org/schemas/domain/qemu/1.0" type="kvm">`, add a `
  <qemu:commandline>` node inside (if missing) and finally paste the script output into it.

- Windows 10 only (QEMU 10.0 patch and newer only): Add `-cpu hv-cppc-stub=on` to the QEMU command line, or add the `hv-cppc-stub=on` feature to the existing `-cpu` option.
  As libvirt XML:
  ```xml
  <qemu:arg value="-cpu"/> <qemu:arg value="hv-cppc-stub=on"/>
  ```
  This feature triggers the correct code path in the Win10 amdppm.sys driver to use CPPC even inside a hypervisor.
  
  Note: Only the patched qemu-system supports several `-cpu` options. Stock QEMU will show an error about not knowing the CPU model.
  
  Note: This custom hypervisor feature will prevent Windows 11 from booting and should only be used for Windows 10 22H2 guests.

- Windows 11 only: Import to the registry (store as a .reg file and run with regedit):
  ```
  Windows Registry Editor Version 5.00
  
  [HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Processor]
  "AllowGuestPerfStates"=dword:00000001
  
  ```
- [unrelated to CPPC] Additional optimization: Add `-cpu hv-no-nonarch-coresharing=on` to the QEMU command line, or add the `hv-no-nonarch-coresharing=on` feature to the existing `-cpu` option. May disable certain SMT side-channel mitigations in the guest OS. If vCPU pinning is configured correctly, such that SMTs are advertised in the topology and have neighboring vCPU IDs, this presumably improves performance without any impact on security (ONLY if pinning is configured correctly!)
  As libvirt XML:
  ```xml
  <qemu:arg value="-cpu"/> <qemu:arg value="hv-no-nonarch-coresharing=on"/>
  ```
  It is auto-enabled up until the QEMU 10.0 patch but not beyond, now that the patch combines several `-cpu` options.

- To find out whether the Windows guest actually uses CPPC-based scheduling, the most effective way is to put load on a single thread while the guest idles. In a script language of your choice, create an endless loop and check if the load consistently appears on the 'best core' in Task Manager. Win10: Start the program twice to check if the two 'best cores' are now loaded, and so on. Win11 is a bit more unpredictable beyond the single 'best' core, but will usually still follow the order. The HWiNFO utility should also show a CPPC core performance ranking in its detail view (though this does not prove whether the OS scheduler behaves).

### Tested configurations
- AMD Ryzen 7950X3D CPU
  - Intel P-/E-Core architectures may also benefit from these patches, but have not been tested. Whether those work out of the box should largely depend on how the intelppm.sys driver behaves. For instance, Intel Thread Director will not be present in the VM. The generic processr.sys driver is more likely to work here.
- QEMU 8.2.2 .. 10.0.0
- Host Linux kernels: `6.6.19-1-MANJARO` (patches for 6.6, 6.7 and 6.8), .., `6.14.6-2-MANJARO`
- Guest OS: Windows 10 22H2
- Guest OS: Windows 11 24H2 requires the QEMU 10.0 patch (older patch versions always enable the hv-cppc-stub)
- Guest OS: Linux guests currently reject the CPPC data as invalid

## Patch details

To make Windows 10 use the CPPC performance values despite being run as a Hyper-V-enlightened VM, a chain of workarounds is required. While booting, the amdppm.sys or processr.sys driver will check for a hypervisor and, if the `CpuManagement` hypervisor capability is not reported through CPUID, the driver will ignore any CPPC information. With `CpuManagement` set, however, the behavior of the bootloader `winload.exe` changes, leading to an early-boot error screen if virtualization-based security is disabled while causing other errors if it is enabled. As a direct workaround, the patched KVM module enables the `CpuManagement` CPUID flag only after observing a predefined number of reads to a Hyper-V CPUID as an indication of boot progess (tuned for Win10 22H2).

Windows 11 makes that workaround largely infeasible, as pci.sys now maps DMA ranges in a way QEMU does not support if `CpuManagement` is present. Luckily, that workaround is not needed anymore. The Windows 11 amdppm driver has a registry option to use CPPC even if a hypervisor is present.

### QEMU patches
- Adds the acpi_cppc device type that provides the ACPI _CPC object carrying the configured core performance indicators. This device also adds some other stub ACPI objects that operating systems expect to be present for CPPC support.

  The [mkparams_cppc_device.py](mkparams_cppc_device.py) script generates a basic device configuration. For detailed documentation on the options, see `hw/acpi/cppc.c` in the QEMU patch file.
- AMD-specific MSRs that are used for CPPC. The default `addrspace=2` setting for the acpi_cppc device will put references to those MSRs in the _CPC object.
- Stub MSRs related to the `CpuManagement` Hyper-V feature, via `hv-cppc-stub` cpu feature. These are present to avoid faults in the guest OS.

### KVM patches
- Adds the `CpuManagement` winload workaround that hides the `CpuManagement` flag for a set amount of reads to the Hyper-V CPUID for each VM boot.
- Enables read/write pass-through for the MPERF, APERF, MPERF_RO and APERF_RO MSRs, since the former two are also referenced by the ACPI _CPC objects emitted by the patched QEMU. These MSRs provide precise clocking information to the guest VM, which could conceivably be abused as a **side-channel**. Writes to these MSRs (usually 0 as value) will be visible to the host and all other VMs, and may cause inconsistent frequency reporting.