#!/usr/bin/env bash
# Run every old-kernel test against the sharun built from this checkout.
#   run-tests.sh [-k "2.6.17 2.6.16"] [-q]
# Always: syscall regression tests and the coreutils/bash AppDir test.
# When the AppImages were built (build-demo.sh gtk2-demo-appimage /
# xvfb-demo-appimage, build-dvdisaster.sh) also: the GUI test and the
# dvdisaster Reed-Solomon round trip. Exit status is non-zero if anything fails.
set -u
here=$(cd "$(dirname "$0")" && pwd)
kernels="2.6.17 2.6.16"; [ "${1:-}" = -k ] && { kernels=$2; shift 2; }
sharun=$here/../../target/x86_64-unknown-linux-musl/release/sharun
[ -x "$sharun" ] || "$here/build-sharun.sh" >/dev/null || exit 1
a=$here/cache/appimages; fail=0
run() { # name cmd...
	name=$1; shift
	if "$@" >"$here/cache/last-test.log" 2>&1; then echo "PASS  $name"
	else echo "FAIL  $name   (log: $(realpath --relative-to=. "$here/cache/last-test.log" 2>/dev/null || echo "$here/cache/last-test.log"))"; cp "$here/cache/last-test.log" "$here/cache/fail-${name//[^a-zA-Z0-9.]/_}.log"; fail=1; fi
}
for k in $kernels; do
	run "$k syscalls"  "$here/test-syscalls.sh" "$sharun" "$k"
	run "$k coreutils" "$here/test-sharun.sh" "$sharun" "$k"
	ls "$a"/gtk2-ng-demo-*.AppImage "$a"/xvfb-demo-*.AppImage >/dev/null 2>&1 &&
		run "$k gtk2 GUI" "$here/test-gui.sh" -k "$k" "$a"/xvfb-demo-x86_64.AppImage "$a"/gtk2-ng-demo-x86_64.AppImage
	ls "$a"/dvdisaster-*.AppImage >/dev/null 2>&1 &&
		run "$k dvdisaster" "$here/test-dvdisaster.sh" -k "$k"
done
exit $fail
