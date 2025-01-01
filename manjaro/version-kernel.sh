#!/bin/bash
source util.sh

shopt -s nullglob

#KERNELVER=6.6.19-1-MANJARO
KERNELVER_INTERACTIVE_SELECT=0
if [[ ! -v KERNELVER ]]; then
	KERNELVER=$(cat .kernelver 2> /dev/null || :)
fi
if [ "$KERNELVER" == "" ] || [ ! -f "/usr/lib/modules/${KERNELVER}/kernelbase" ]; then
	KERNELVER_INTERACTIVE_SELECT=1
	KERNELVER="$(uname -r)"
fi

# Interactive kernel selection into KERNELVER.
# If detected as installed, $KERNELVER will be selected as default.
function interactive_kernelver {
	local KERNELBASE_PATHS=(/usr/lib/modules/*/kernelbase)
	local KERNELVERS_AVAILABLE=()
	local IDX=0
	local IDX_PRESEL=-1
	for KERNELBASE_PATH in "${KERNELBASE_PATHS[@]}"; do
		local CURKERNELVER="$(basename "${KERNELBASE_PATH::-11}")"
		KERNELVERS_AVAILABLE+=("$CURKERNELVER")
		if [ "$CURKERNELVER" == "$KERNELVER" ]; then
			IDX_PRESEL=$IDX
		fi
		IDX=$(($IDX + 1))
	done
	local KERNELVERS_AVAILABLE_COUNT=${#KERNELVERS_AVAILABLE[@]}
	if [ ${KERNELVERS_AVAILABLE_COUNT} -eq 0 ]; then
		echo "Found no available kernel versions" >&2
		return 1
	fi
	if [ $AUTOYES -eq 1 ]; then
		if [ $IDX_PRESEL -ge 0 ]; then
			# Default (=current) kernel version is available
			return 0
		fi
		echo "Did not detect the default kernel version $KERNELVER as installed (??)" >&2
		return 1
	fi
	declare -g SUBARG_OPTIONS=("${KERNELVERS_AVAILABLE[@]}")
	declare -g FNRESULT=-1
	interactive_select_single_element FNRESULT "Select a kernel version to target:" SUBARG_OPTIONS $IDX_PRESEL
	if [ $FNRESULT -lt 0 ] || [ $FNRESULT -ge ${KERNELVERS_AVAILABLE_COUNT} ]; then
		echo "Version selection failed" >&2
		return 1
	fi
	KERNELVER="${KERNELVERS_AVAILABLE[$FNRESULT]}"
}
if [ ${KERNELVER_INTERACTIVE_SELECT} -eq 1 ]; then
	interactive_kernelver
	echo "$KERNELVER" > .kernelver
fi
echo "Selected kernel version ${KERNELVER}"

#KERNELVER_BRANCH=6.6
KERNELVER_BRANCH=$(echo "$KERNELVER" | grep -oP '^[0-9]+\.[0-9]+')
#LINUXVER=linux-6.6
LINUXVER=linux-${KERNELVER_BRANCH}

#MKINITCPIO_NAME=linux66
MKINITCPIO_NAME=$(cat "/usr/lib/modules/${KERNELVER}/pkgbase")


# Declare and select patches
# X0: undecided, default to 0
# X1: undecided, default to 1
# 0: don't apply
# 1: apply

declare -A patchsel
declare -A patchsel_desc
patchsel_keys=()

KVMPATCH_CPPC=$(pwd)/../linux-${KERNELVER_BRANCH}-kvm-cppc.patch
#-> Additional logic for patch file choice if compatibility breaks between minor kernel releases.
if [ ${KERNELVER:0:4} == '6.9.' ] && ([ ${KERNELVER:4:1} -ge 6 ] || [ ${KERNELVER:5:1} != '-' ]); then
	#6.9.6+: svm.h
	KVMPATCH_CPPC=$(pwd)/../linux-6.9.6-kvm-cppc.patch
fi
patchsel[KVMCPPC]=X1
patchsel_desc[KVMCPPC]="KVM: CPPC support hacks"
patchsel_keys+=(KVMCPPC)

KVMPATCH_REGRESSION_612=""
VFIOPCICORE_REGRESSION_612=""
if [ ${KERNELVER:0:5} == '6.12.' ] || [ ${KERNELVER:0:5} == '6.13.' ]; then
	#Apply patch by SimonP, see https://bbs.archlinux.org/viewtopic.php?id=301352&p=2
	#NOTE: Will likely get fixed at some point in the 6.12 (LTS) cycle, maybe 6.13 too.
	KVMPATCH_REGRESSION_612=$(pwd)/../linux-6.12-kvm-amd-regression.patch
	patchsel[KVMREGRESSION612]=X0
	patchsel_desc[KVMREGRESSION612]="KVM: Kernel 6.12+ regression fix (affects some AMD CPU systems but not all)"
	patchsel_keys+=(KVMREGRESSION612)
	
	#Fix regression from commit f9e54c3a2f5b79ecc57c7bc7d0d3521e461a2101 "vfio/pci: implement huge_fault support", first included in 6.12
	# Patch by Alex Williamson, https://lore.kernel.org/regressions/20241231090733.5cc5504a.alex.williamson@redhat.com/
	VFIOPCICORE_REGRESSION_612=$(pwd)/../linux-6.12-vfio-pci-core-regression.patch
	patchsel[VFIOPCIREGRESSION612]=X1
	patchsel_desc[VFIOPCIREGRESSION612]="vfio-pci: Kernel 6.12+ regression fix for qemu <= 9.1"
	patchsel_keys+=(VFIOPCIREGRESSION612)
fi

function setpatchsel_check {
	local key="$1"
	local val="$2"
	# Only update existing entries
	if [ "${patchsel[$key]+1}" ]; then
		case "$val" in
			X0 ) patchsel[$key]=X0;;
			X1 ) patchsel[$key]=X1;;
			1 ) patchsel[$key]=1;;
			* ) patchsel[$key]=0;;
		esac
	fi
}

# Parse the .patchsel file
PATCHSEL_LINEREGEX='^([0-9A-Z_]+)=(X0|X1|1|0)$'
if [ -f .patchsel ]; then
	while IFS="" read -r patchsel_curline; do
		if [[ "$patchsel_curline" =~ $PATCHSEL_LINEREGEX ]]; then
			setpatchsel_check "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
		elif [ "$patchsel_curline" != "" ]; then
			echo "Encountered an unexpected line in .patchsel" >&2
		fi
	done < .patchsel
fi

# Apply settings from environment variables
if [[ -v PATCH_KVMCPPC_ENABLE ]]; then setpatchsel_check KVMCPPC "${PATCH_KVMCPPC_ENABLE}"; fi
if [[ -v PATCH_KVMREGRESSION612_ENABLE ]]; then setpatchsel_check KVMREGRESSION612 "${PATCH_KVMREGRESSION612_ENABLE}"; fi
if [[ -v PATCH_VFIOPCIREGRESSION612_ENABLE ]]; then setpatchsel_check VFIOPCIREGRESSION612 "${PATCH_VFIOPCIREGRESSION612_ENABLE}"; fi

# Apply defaults for undecided selections
PATCHSEL_UNDECIDED=0
for patchkey in "${patchsel_keys[@]}"; do
	case "${patchsel[$patchkey]}" in
		X0 ) PATCHSEL_UNDECIDED=1; patchsel[$patchkey]=0;;
		X1 ) PATCHSEL_UNDECIDED=1; patchsel[$patchkey]=1;;
	esac
done
PATCHSEL_INTERACTIVE=$PATCHSEL_UNDECIDED

# Interactive selection of active patches. Updates the .patchsel file.
function interactive_patchsel {
	interactive_toggle_element_list patchsel "Patch selection:" patchsel_keys patchsel_desc
	rm -f .patchsel
	for patchkey in "${patchsel_keys[@]}"; do
		echo "${patchkey}=${patchsel[$patchkey]}" >> .patchsel
	done
}
if [ ${PATCHSEL_INTERACTIVE} -eq 1 ] && [ $AUTOYES -eq 0 ]; then
	interactive_patchsel
fi
