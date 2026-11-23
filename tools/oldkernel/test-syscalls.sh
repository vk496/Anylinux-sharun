#!/usr/bin/env bash
# Regression tests for compat-layer syscall emulation: tiny static programs
# (tests/*.c, built with musl-gcc) run through sharun's AppRun in the guest.
# Each program must print its checks and exit 0 when the semantics are right.
#   test-syscalls.sh <sharun> [kernel-id]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
sharun=$(realpath "$1"); kernel=${2:-2.6.17}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
app=$tmp/app; mkdir -p "$app"
cp "$sharun" "$app/sharun"; ln "$app/sharun" "$app/AppRun"
for src in "$here"/tests/*.c; do musl-gcc -static -O2 "$src" -o "$app/$(basename "${src%.c}")"; done
cat >"$tmp/guest.sh" <<'G'
rc=0
for t in /opt/app/*; do
	case $t in */sharun|*/AppRun|*/AppRun.sh) continue ;; esac
	printf '#!/bin/sh\nexec %s\n' "$t" >/opt/app/AppRun.sh
	timeout -s KILL 15 /opt/app/AppRun >/tmp/out 2>&1; r=$?; out=$(cat /tmp/out)
	if [ $r = 0 ]; then echo "ok:   $(basename $t)"; else echo "FAIL: $(basename $t) rc=$r: $out"; rc=1; fi
done
exit $rc
G
"$here/run.sh" -k "$kernel" -f "$app:app" -f "$tmp/guest.sh:guest.sh" -- 'sh /opt/guest.sh'
