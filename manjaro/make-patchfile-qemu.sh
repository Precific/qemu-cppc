source version.sh

set -e
OUTDIR=$(pwd)

pushd qemu-arch-package/src
QEMUDIR_UNPATCHED=../../qemu
QEMUDIR_PATCHED=$QEMUVER
#QEMUDIR_UNPATCHED=$QEMUVER
#rm -rf $QEMUDIR_UNPATCHED
#tar -xf $QEMUVER.tar.xz
#QEMUDIR_PATCHED=../../qemu

diff --unified --recursive --text --new-file \
 --exclude=.git --exclude=roms --exclude=lcitool \
 $QEMUDIR_UNPATCHED $QEMUDIR_PATCHED > "$OUTDIR/$QEMUVER-cppc.patch" || :
#diff for some reason returns non-zero even if everything ends up fine?
popd
