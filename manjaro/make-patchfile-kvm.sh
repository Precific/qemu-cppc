#!/bin/bash
set -e
source version-kernel.sh

OUTDIR=$(pwd)
PACKAGE_SUBDIR=kernel-manjaro-package-${KERNELVER_BRANCH}

LINUXDIR_PATCHED="$(pwd)/$PACKAGE_SUBDIR/src/$LINUXVER"
LINUXDIR_UNPATCHED="$(pwd)/$LINUXVER"

if [ ! -d "$LINUXDIR_UNPATCHED" ]; then
	echo "ERROR: Could not find the unpatched directory at ./$LINUXVER to compare against $PACKAGE_SUBDIR/src/$LINUXVER"
	echo "Hint: After running download-sources-kvm.sh, copy $PACKAGE_SUBDIR/src/$LINUXVER to ./$LINUXVER."
	exit 1
fi

if [[ "$(cat "$LINUXDIR_UNPATCHED/.config" | grep "# Linux/x86 ")" != "$(cat "$LINUXDIR_PATCHED/.config" | grep "# Linux/x86 ")" ]]; then
	echo 'ERROR: The linux version strings do not match between the unpatched and the patched directory.'
	exit 1
fi

echo "Copying all unpatched and patched files seen by git..."
TEMPBASE="$(pwd)/make-patchfile_temp"
LINUXDIR_UNPATCHED_COPYTO="${TEMPBASE}/${LINUXVER}_unpatched"
LINUXDIR_PATCHED_COPYTO="${TEMPBASE}/${LINUXVER}"

if [ ! -d "$LINUXDIR_UNPATCHED_COPYTO" ] || [[ "$(cat "$LINUXDIR_UNPATCHED_COPYTO/.config" | grep "# Linux/x86 ")" != "$(cat "$LINUXDIR_PATCHED/.config" | grep "# Linux/x86 ")" ]]; then
	rm -rf "$LINUXDIR_UNPATCHED_COPYTO"
	mkdir -p "$LINUXDIR_UNPATCHED_COPYTO"
	cd "$LINUXDIR_UNPATCHED"
	[ -d .git ] || git init > /dev/null
	git ls-files -z --cached --others --exclude-standard | xargs -0 cp --parents -r -t "$LINUXDIR_UNPATCHED_COPYTO"
	cp .config "$LINUXDIR_UNPATCHED_COPYTO"
fi

rm -rf "$LINUXDIR_PATCHED_COPYTO"
mkdir -p "$LINUXDIR_PATCHED_COPYTO"
cd "$LINUXDIR_PATCHED"
[ -d .git ] || git init > /dev/null
git ls-files -z --cached --others --exclude-standard | xargs -0 cp --parents -r -t "$LINUXDIR_PATCHED_COPYTO"

PATCHFILE="$OUTDIR/$LINUXVER-kvm-cppc.patch"
rm -f "$PATCHFILE"

echo "Comparing, saving patch file to ${PATCHFILE}..."

cd "$TEMPBASE"
diff -x '*.orig' -x '*.rej' -x '.config' --unified --recursive --text --new-file \
 "${LINUXVER}_unpatched" "${LINUXVER}" > "$PATCHFILE" || :

#diff for some reason returns non-zero even if everything ends up fine?
