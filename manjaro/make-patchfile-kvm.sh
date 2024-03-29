source version.sh

set -e
OUTDIR=$(pwd)

pushd kernel-manjaro-package-${KERNELVER_BRANCH}
cd src
LINUXDIR_PATCHED=$LINUXVER
LINUXDIR_UNPATCHED=../../$LINUXVER

if [[ "$(cat $LINUXDIR_UNPATCHED/.config | grep "# Linux/x86 ")" == "$(cat $LINUXDIR_PATCHED/.config | grep "# Linux/x86 ")" ]]; then
	diff -x '*.orig' -x '*.rej' --unified --recursive --text --new-file \
	 $LINUXDIR_UNPATCHED $LINUXDIR_PATCHED > "$OUTDIR/$LINUXVER-kvm-cppc.patch" || :
	#diff for some reason returns non-zero even if everything ends up fine?
else
	echo 'ERROR: The linux version strings do not match between the unpatched and the patched directory.'
fi

popd