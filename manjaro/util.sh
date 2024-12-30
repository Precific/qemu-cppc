#!/bin/bash
if [[ -v UTIL_SH ]]; then
	return 0
fi
UTIL_SH=1

AUTOYES=0
for arg in "$@"; do
	if [[ "$arg" == "-y" ]]; then
		AUTOYES=1
	fi
done

# Interactive "continue or exit" query
# args: (none)
function ask_continue_or_exit {
	if [ $AUTOYES -eq 1 ]; then
		return 0
	fi
	while true; do
		read -p "Do you want to continue? [y/n]: " answer
		if [[ "$answer" =~ ^[yY]$ ]]; then
			return 0
		elif [[ "$answer" =~ ^[nN]$ ]]; then
			echo "Aborted"
			exit 1
		fi
		echo "?"
	done
}

# Reads each line and prepends a set number of spaces as indentation.
# Intended for use by piping in from the fmt command.
# args: $1 - Indentation width
function readprint_multiline {
	local FIRSTLINE=1
	local LINEINDENTW="$1"
	while IFS="" read line; do
		[ $FIRSTLINE -eq 1 ] || printf "%${LINEINDENTW}s" ""
		printf "%s\n" "$line"
		FIRSTLINE=0
	done
}

# Interactive selection of exactly one element out of an array.
# args:
#  $1 - name of return value (used as nameref); will be set to the selected element's index
#  $2 - query text to show to the user
#  $3 - array of elements (used as nameref); each entry is a string to display to the user
#  $4 - default selection index, or -1 if there is no default
function interactive_select_single_element {
	local -n IDX_RET=$1
	local QUERY=$2
	local -n ALLELEMENTS=$3
	local IDX_PRESEL=$4

	echo "$QUERY"
	IDX_RET=-1
	local IDX=0
	local ALLELEMENTS_COUNT=${#ALLELEMENTS[@]}
	local IDX_MAXDIGITS_CEIL=${#ALLELEMENTS_COUNT}
	for ELEMENT in "${ALLELEMENTS[@]}"; do
		local ISSEL=" "
		if [ $IDX -eq $IDX_PRESEL ]; then
			ISSEL="*"
		fi
		printf "%s%${IDX_MAXDIGITS_P1}s: %s\n" "${ISSEL}" ${IDX} "${ELEMENT}"
		IDX=$(($IDX + 1))
	done
	while true; do
		local answer=""
		read -p "Index (0 .. $((${ALLELEMENTS_COUNT}-1))): " answer
		if [ "$answer" == "" ] && [ $IDX_PRESEL -ge 0 ]; then
			answer=${IDX_PRESEL}
		elif ! [[ "$answer" =~ ^[0-9]+$ ]]; then
			echo "Please enter a valid index."
			continue
		elif [ $answer -ge ${ALLELEMENTS_COUNT} ]; then
			echo "Please enter an index in 0 .. $((${ALLELEMENTS_COUNT}-1))"
			continue
		fi
		IDX_RET="${answer}"
		break
	done
}

# Interactive selection of any number of elements out of an array.
# The selection is stored as an associative mask array; an element is considered included iff its mask entry is 1.
# args:
#  $1 - name of associative mask array (used as nameref) with 0/1 values, indexed by the element key;
#       will be updated to reflect the user's selection
#  $2 - query text to show to the user
#  $3 - array of element keys
#  $4 - associative array of human-readable descriptions, indexed by the element key;
#       if a key has no associated description, the key itself will be shown to the user
function interactive_toggle_element_list {
	local -n SELMASK_RET=$1
	local QUERY=$2
	local -n ALLKEYS=$3
	local -n KEYDESCS=$4

	local IDX_MAXDIGITS_CEIL=${#ALLKEYS[@]}
	local IDX_MAXDIGITS_CEIL=${#IDX_MAXDIGITS_CEIL}
	while true; do
		local NCOLS=$(tput cols 2> /dev/null || echo 120)
		local IDX=0
		echo "$QUERY"
		for elementkey in "${ALLKEYS[@]}"; do
			local ISSEL=" "
			if [ "${SELMASK_RET[$elementkey]}" == "1" ]; then
				ISSEL="*"
			fi
			local ENTRYPREFIX=""
			#Print entry line start "<ISSEL><IDX> - "
			printf -v ENTRYPREFIX "%s%${IDX_MAXDIGITS_CEIL}s - " "$ISSEL" "$IDX"
			printf "%s" "$ENTRYPREFIX"
			local ENTRYPREFIX_LEN=${#ENTRYPREFIX}
			#Print entry description with multi-line formatting as needed
			echo "${KEYDESCS[$elementkey]}" | fmt -w $(($NCOLS<=$ENTRYPREFIX_LEN ? 1 : ($NCOLS - $ENTRYPREFIX_LEN))) | readprint_multiline ${#ENTRYPREFIX}
			IDX=$(($IDX + 1))
		done

		local answer=""
		local answer_regex='^[0-9]+( [0-9]+)*$'
		read -p "Toggle indices (0 .. $((${#ALLKEYS[@]}-1))) or continue: " answer
		if [ "$answer" == "" ]; then
			break
		elif ! [[ "$answer" =~ $answer_regex ]]; then
			echo "Please enter a set of indices, separated by spaces."
			continue
		else
			for keyidx in $answer; do
				if [ $keyidx -ge ${#ALLKEYS[@]} ]; then
					echo "Please enter indices in 0 .. $((${#ALLKEYS[@]}-1))"
					break
				fi
				case "${SELMASK_RET[${ALLKEYS[$keyidx]}]}" in
					0 ) SELMASK_RET[${ALLKEYS[$keyidx]}]=1;;
					1 ) SELMASK_RET[${ALLKEYS[$keyidx]}]=0;;
				esac
			done
		fi
	done
}
