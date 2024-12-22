#!/bin/bash

shopt -s nullglob

#KERNELVER=6.6.19-1-MANJARO
KERNELVER_NEEDS_SELECTION=0
if [[ ! -v KERNELVER ]]; then
	KERNELVER=$(cat .kernelver 2> /dev/null || :)
fi
if [ "$KERNELVER" == "" ] || [ ! -f "/usr/lib/modules/${KERNELVER}/kernelbase" ]; then
	KERNELVER_NEEDS_SELECTION=1
	KERNELVER=$(uname -r)
fi
function interactive_kernelver {
	local KERNELBASE_PATHS=(/usr/lib/modules/*/kernelbase)
	local KERNELVERS_AVAILABLE=()
	for KERNELBASE_PATH in "${KERNELBASE_PATHS[@]}"; do
		KERNELVERS_AVAILABLE+=("$(basename "${KERNELBASE_PATH::-11}")")
	done
	local KERNELVERS_AVAILABLE_COUNT=${#KERNELVERS_AVAILABLE[@]}
	if [ ${KERNELVERS_AVAILABLE_COUNT} -eq 0 ]; then
		echo "Found no available kernel versions"
		exit 1
	fi
	echo "Select a kernel version to target:"
	local IDX=0
	local IDX_PRESEL=-1
	local IDX_MAXDIGITS=$((${KERNELVERS_AVAILABLE_COUNT} - 1))
	local IDX_MAXDIGITS=${#IDX_MAXDIGITS}
	for KERNELVER_OPTION in "${KERNELVERS_AVAILABLE[@]}"; do
		local ISSEL=" "
		if [ "$KERNELVER_OPTION" == "$KERNELVER" ]; then
			IDX_PRESEL=$IDX
			ISSEL="*"
		fi
		printf "%s%${#KERNELVERS_AVAILABLE_COUNT}s: %s\n" "${ISSEL}" ${IDX} "${KERNELVER_OPTION}"
		IDX=$(($IDX + 1))
	done
	while true; do
		local answer=""
		read -p "Index (0 .. $((${KERNELVERS_AVAILABLE_COUNT}-1))): " answer
		if [ "$answer" == "" ] && [ $IDX_PRESEL -ge 0 ]; then
			answer=${IDX_PRESEL}
		elif ! [[ "$answer" =~ ^[0-9]+$ ]]; then
			echo "Please enter a valid index."
			continue
		elif [ $answer -ge ${KERNELVERS_AVAILABLE_COUNT} ]; then
			echo "Please enter an index in 0 .. $((${KERNELVERS_AVAILABLE_COUNT}-1))"
			continue
		fi
		KERNELVER="${KERNELVERS_AVAILABLE[${answer}]}"
		break
	done
}
if [ ${KERNELVER_NEEDS_SELECTION} -eq 1 ]; then
	interactive_kernelver
	echo "$KERNELVER" > .kernelver
fi
echo "Selected kernel version ${KERNELVER}"

#KERNELVER_BRANCH=6.6
KERNELVER_BRANCH=$(echo "$KERNELVER" | grep -oP '^[0-9]+\.[0-9]+')
#LINUXVER=linux-6.6
LINUXVER=linux-${KERNELVER_BRANCH}

KVMPATCH=$(pwd)/../linux-${KERNELVER_BRANCH}-kvm-cppc.patch
#-> Additional logic for patch file choice if compatibility breaks between minor kernel releases.
if [ ${KERNELVER:0:4} == '6.9.' ] && ([ ${KERNELVER:4:1} -ge 6 ] || [ ${KERNELVER:5:1} != '-' ]); then
	#6.9.6+: svm.h
	KVMPATCH=$(pwd)/../linux-6.9.6-kvm-cppc.patch
fi
KVMPATCH_REGRESSION_612=""
VFIOPCICORE_REGRESSION_612=""
if [ ${KERNELVER:0:5} == '6.12.' ] || [ ${KERNELVER:0:5} == '6.13.' ]; then
	#Apply patch by SimonP, see https://bbs.archlinux.org/viewtopic.php?id=301352&p=2
	#NOTE: Will likely get fixed at some point in the 6.12 (LTS) cycle, maybe 6.13 too.
	#KVMPATCH_REGRESSION_612=$(pwd)/../linux-6.12-kvm-amd-regression.patch
	
	#Undo commit f9e54c3a2f5b79ecc57c7bc7d0d3521e461a2101 "vfio/pci: implement huge_fault support", first included in 6.12
	VFIOPCICORE_REGRESSION_612=$(pwd)/../linux-6.12-vfio-pci-core-regression.patch
	
fi

#MKINITCPIO_NAME=linux66
MKINITCPIO_NAME=$(cat "/usr/lib/modules/${KERNELVER}/pkgbase")
