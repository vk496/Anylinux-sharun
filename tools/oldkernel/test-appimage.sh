#!/usr/bin/env bash
# Run an Anylinux-AppImages AppImage in the old-kernel guest, exactly as a user
# would: ./app.AppImage [args]. The runtime does its own extract-and-run when
# there is no FUSE (there is none in the guest); nothing is unpacked by hand.
#   test-appimage.sh [-k KERNEL] [-d] <file.AppImage> [app args...]
# -d turns on the compat layer's debug log (SHARUN_OLD_KERNEL_COMPAT_DEBUG=1).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
kernel=2.6.17 dbg=0
while getopts k:d o; do case $o in k) kernel=$OPTARG ;; d) dbg=1 ;; *) exit 2 ;; esac; done
shift $((OPTIND - 1)); img=$(realpath "$1"); shift
args=""; for a in "$@"; do args+=" '${a//\'/\'\\\'\'}'"; done
env=""; [ $dbg = 1 ] && env="SHARUN_OLD_KERNEL_COMPAT_DEBUG=1 "
exec "$here/run.sh" -k "$kernel" -m 1024 -f "$img:app.AppImage" -- "${env}/opt/app.AppImage$args"
