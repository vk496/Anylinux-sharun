#!/usr/bin/env bash
# Run `sharun --compat-exec` directly (no AppRun) on an old kernel, with a control run without it.
#   test-compat-exec.sh <sharun-binary> <kernel-id>
set -eu
oldk=$(cd "$(dirname "$0")" && pwd)
sharun=$(realpath "$1"); kernel=$2
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
app=$tmp/AppDir; mkdir -p "$app/bin" "$app/lib" "$app/shared/bin"
cp "$sharun" "$app/sharun"
for p in ls bash; do
	b=$(realpath "/usr/bin/$p"); cp "$b" "$app/shared/bin/$p"; ln "$app/sharun" "$app/bin/$p"
	for l in $(ldd "$b" | awk '{for(i=1;i<=NF;i++) if($i ~ /^\//) print $i}'); do cp -L "$l" "$app/lib/"; done
done
cp "$sharun" "$tmp/sharun"
cat >"$tmp/guest.sh" <<'G'
echo "== with --compat-exec"
/opt/sharun --compat-exec /opt/AppDir/bin/bash -c 'echo bash-ok $((6*7)); /opt/AppDir/bin/ls -d /tmp /opt'; echo "rc=$?"
echo "== without (control)"
/opt/AppDir/bin/bash -c 'echo bash-ok'; echo "rc=$?"
echo "== no command"
/opt/sharun --compat-exec; echo "rc=$?"
G
"$oldk/run.sh" -k "$kernel" -N -f "$tmp/sharun:sharun" -f "$app:AppDir" -f "$tmp/guest.sh:guest.sh" -- 'sh /opt/guest.sh'
