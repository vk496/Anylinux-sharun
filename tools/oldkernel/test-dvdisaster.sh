#!/usr/bin/env bash
# Heavy real-world check: the dvdisaster AppImage (speed47/dvdisaster PR #219,
# built by build-dvdisaster.sh) does a full Reed-Solomon round trip in the guest:
# random image -> RS03 create -> test -> damage -> fix -> checksum must match.
# Uses a CPU model with AVX2 by default, so dvdisaster's SIMD dispatch (and the
# XGETBV an old kernel never enabled) is exercised too.
#   test-dvdisaster.sh [-k KERNEL] [-C CPU] [-x THREADS] [<dvdisaster.AppImage>]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
kernel=2.6.17 cpu=max threads=2
while getopts k:C:x: o; do case $o in k) kernel=$OPTARG ;; C) cpu=$OPTARG ;; x) threads=$OPTARG ;; *) exit 2 ;; esac; done
shift $((OPTIND - 1))
img=${1:-$(ls "$here"/cache/appimages/dvdisaster-*-x86_64.AppImage | head -1)}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/guest.sh" <<G
cd /tmp
DV=/opt/dv.AppImage
step() { echo "== \$*"; }
die() { echo "FAIL: \$*"; exit 1; }
dd if=/dev/urandom of=img.iso bs=2048 count=4096 2>/dev/null   # 8 MiB "disc"
md5sum img.iso | cut -d' ' -f1 >orig.md5

step "create RS03 ecc (-x $threads)"
\$DV -i img.iso -e img.ecc -mRS03 -o file -n 25% -x $threads --no-progress -c || die "create"
[ -s img.ecc ] || die "no ecc file written"

step "test intact image against ecc"
\$DV -i img.iso -e img.ecc -mRS03 --no-progress -t || die "test of intact image"

step "damage 50 sectors"
dd if=/dev/zero of=img.iso bs=2048 seek=100 count=50 conv=notrunc 2>/dev/null
[ "\$(md5sum img.iso | cut -d' ' -f1)" != "\$(cat orig.md5)" ] || die "damage had no effect"

step "fix"
\$DV -i img.iso -e img.ecc -mRS03 -x $threads --no-progress -f || die "fix"
[ "\$(md5sum img.iso | cut -d' ' -f1)" = "\$(cat orig.md5)" ] || die "repaired image differs from the original"
echo "ALL OK: image repaired bit-exact"
G
"$here/run.sh" -k "$kernel" -C "$cpu" -m 1536 -t 900 -f "$img:dv.AppImage" -f "$tmp/guest.sh:guest.sh" -- 'sh /opt/guest.sh' 2>&1 \
	| tee "$tmp/out" | grep -v '^CRC error\|repaired sectors:\|^[0-9]*%\|memfd\|FUSE\|Trying to extract\|child-subreaper\|CA Certificates\|enabled old kernel\|SeaBIOS\|Booting\|^$' | cut -c1-200
grep -q '^ALL OK' "$tmp/out"
