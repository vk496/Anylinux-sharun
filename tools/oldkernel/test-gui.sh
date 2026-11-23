#!/usr/bin/env bash
# Run a GUI AppImage in the old-kernel guest against an Xvfb AppImage and save a
# screenshot of what it drew.
#   test-gui.sh [-k KERNEL] [-C CPU] [-m MEM] [-w SECS] [-o out.png] <xvfb.AppImage> <app.AppImage> [app args...]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
kernel=2.6.17 cpu=qemu64 mem=1536 wait=12 out=$here/cache/screenshot.png
while getopts k:C:m:w:o: o; do case $o in k) kernel=$OPTARG ;; C) cpu=$OPTARG ;; m) mem=$OPTARG ;; w) wait=$OPTARG ;; o) out=$(realpath -m "$OPTARG") ;; *) exit 2 ;; esac; done
shift $((OPTIND - 1)); xvfb=$(realpath "$1"); app=$(realpath "$2"); shift 2
args=""; for a in "$@"; do args+=" '${a//\'/\'\\\'\'}'"; done
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/guest.sh" <<G
mkdir -p /tmp/fb /tmp/.X11-unix /usr/bin
# Xvfb runs "sh -c /usr/bin/xkbcomp ..." with the guest shell, which cannot see into the AppImage: invoking the AppImage under that name makes AppRun pick the bundled xkbcomp
ln -sf /opt/xvfb.AppImage /usr/bin/xkbcomp
/opt/xvfb.AppImage :99 -screen 0 800x600x24 -fbdir /tmp/fb -nolisten tcp >/tmp/xvfb.log 2>&1 &
i=0; while [ ! -S /tmp/.X11-unix/X99 ] && [ \$i -lt 60 ]; do sleep 1; i=\$((i+1)); done
echo "X socket after \${i}s: \$(ls /tmp/.X11-unix)"
DISPLAY=:99 /opt/app.AppImage$args >/tmp/app.log 2>&1 &
app=\$!
sleep $wait
if kill -0 \$app 2>/dev/null; then echo "app still running after $wait s"; else echo "app EXITED early"; fi
echo "--- app.log"; tail -n 15 /tmp/app.log
echo "--- xvfb.log"; tail -n 5 /tmp/xvfb.log
echo "--- screenshot"
echo SHOT-BEGIN; gzip -c /tmp/fb/Xvfb_screen0 | base64; echo SHOT-END
kill \$app 2>/dev/null; exit 0
G
log=$tmp/log
"$here/run.sh" -k "$kernel" -C "$cpu" -m "$mem" -t 400 -f "$xvfb:xvfb.AppImage" -f "$app:app.AppImage" -f "$tmp/guest.sh:guest.sh" -- 'sh /opt/guest.sh' 2>&1 | tee "$log" | sed '/SHOT-BEGIN/,/SHOT-END/d'
grep -q 'app still running' "$log" || { echo "FAIL: the app did not stay up"; exit 1; }
grep -q SHOT-BEGIN "$log" || { echo "FAIL: no screenshot"; exit 1; }
sed -n '/^SHOT-BEGIN/,/^SHOT-END/p' "$log" | sed '1d;$d' | tr -d '\r' | base64 -d | gunzip | python3 "$here/xwd2png.py" >"$out" && echo "screenshot: $out"
