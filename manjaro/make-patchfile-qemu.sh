source version.sh

set -e
OUTDIR=$(pwd)

pushd qemu-arch-package/src
QEMUDIR_UNPATCHED=../../$QEMUVER
QEMUDIR_PATCHED=$QEMUVER

if [ ! -d "$LINUXDIR_UNPATCHED" ]; then
	popd
	echo "ERROR: Could not find the unpatched directory at ./$QEMUVER to compare against qemu-arch-package/src/$QEMUVER"
	echo "Hint: After download-sources-kvm.sh, copy qemu-arch-package/src/$QEMUVER to ./$QEMUVER."
	exit 1
fi

diff --unified --recursive --text --new-file \
 --exclude=.git --exclude=roms --exclude=lcitool \
 $QEMUDIR_UNPATCHED $QEMUDIR_PATCHED > "$OUTDIR/$QEMUVER-cppc.patch" || :
#diff for some reason returns non-zero even if everything ends up fine?
popd
