#!/usr/bin/env bash
# Run host glibc programs through sharun inside the old-kernel guest.
#   test-sharun.sh <sharun-binary> [kernel-id]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
sharun=$(realpath "$1"); kernel=${2:-2.6.17}
progs=(echo ls cp cat sort sha256sum bash)

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
app=$tmp/AppDir; mkdir -p "$app/bin" "$app/lib" "$app/shared/bin"
cp "$sharun" "$app/sharun"
for p in "${progs[@]}"; do
	b=$(realpath "/usr/bin/$p")
	cp "$b" "$app/shared/bin/$p"; ln "$app/sharun" "$app/bin/$p"
	for l in $(ldd "$b" | awk '{for(i=1;i<=NF;i++) if($i ~ /^\//) print $i}'); do cp -L "$l" "$app/lib/"; done
done
ln "$app/sharun" "$app/AppRun"
printf '#!/bin/sh\np=$1; shift\nexec /opt/AppDir/bin/$p "$@"\n' >"$app/AppRun.sh"

cat >"$tmp/guest.sh" <<'G'
fail=0
t() { # desc, expected, cmd...
	d=$1; e=$2; shift 2
	got=$(env -i PATH=/nonexistent "$@" 2>/tmp/err); rc=$?
	if [ "$rc" = 0 ] && [ "$got" = "$e" ]; then echo "ok:   $d"
	else echo "FAIL: $d (rc=$rc got='$got') $(tr "\n" " " </tmp/err)"; fail=1; fi
}
A=/opt/AppDir/AppRun
t echo       hello      $A echo hello
t cat        data       /bin/sh -c "echo data >/tmp/f; $A cat /tmp/f"
t cp         data       /bin/sh -c "$A cp /tmp/f /tmp/g && /bin/cat /tmp/g"
t ls         f          /bin/sh -c "/bin/mkdir /tmp/d; /bin/touch /tmp/d/f; $A ls /tmp/d"
t sort       "a
b"           /bin/sh -c "printf 'b\na\n' | $A sort"
t sha256sum  "$(printf abc | /bin/sha256sum | /bin/cut -d' ' -f1)" /bin/sh -c "printf abc | $A sha256sum | /bin/cut -d' ' -f1"
t bash       42         $A bash -c 'echo $((6*7))'
exit $fail
G
"$here/run.sh" -k "$kernel" -f "$app:AppDir" -f "$tmp/guest.sh:guest.sh" -- 'sh /opt/guest.sh'
