#!/usr/bin/env bash
# Check a sharun release inside real AppImages, run as a user would (no outer tracer).
# The AppImages must already carry that sharun and a runtime that works on old kernels:
#   SHARUN=<release sharun> IN=<dir> repack-runtime.sh <uruntime> <appdir>
#   test-release.sh <appdir> [kernel...]      (default kernels: 2.6.0 2.6.1)
# Uses KVM when /dev/kvm is writable. Logs go to <appdir>/logs.
set -u
here=$(cd "$(dirname "$0")" && pwd)
dir=$(realpath "$1"); shift
[ $# -gt 0 ] || set -- 2.6.0 2.6.1
export OLDKERNEL_TRACE=0
mkdir -p "$dir/logs"
one() { ls "$dir/$1"*.AppImage | head -1; }

# run <app prefix> <guest command, output in /tmp/o> <regex expected in the output>
run() {
	"$here/run.sh" -k "$k" -C host -m 3584 -t 120 -f "$(one "$1"):app.AppImage" -- \
		"ifconfig lo 127.0.0.1 up; mount -o remount,size=2600m /tmp; ln -s /bin/busybox /usr/bin/env
		 export DISABLE_AUTO_UPDATES=1 HOME=/tmp/home; mkdir -p \$HOME; cd /tmp
		 $2; echo rc=\$?; cat /tmp/o" >"$log" 2>&1
	grep -q '^rc=0' "$log" && grep -qE "$3" "$log"
}

fail=0
for k; do
	for t in dvdisaster gtk2 syncthing VSCodium Firefox claude Pinta; do
		log=$dir/logs/$k-$t.log; s=$SECONDS
		case $t in
		dvdisaster) "$here/test-dvdisaster.sh" -k "$k" -C host "$(one dvdisaster)" >"$log" 2>&1 ;;
		gtk2) "$here/test-gui.sh" -k "$k" -C host -o "$dir/logs/$k-gtk2.png" "$(one xvfb)" "$(one gtk2)" >"$log" 2>&1 ;;
		syncthing) run syncthing '/opt/app.AppImage generate --home=/tmp/st </dev/null >/tmp/o 2>&1 && ls /tmp/st/config.xml >>/tmp/o' '/tmp/st/config.xml' ;;
		VSCodium) run VSCodium '/opt/app.AppImage --no-sandbox --user-data-dir /tmp/u --version </dev/null >/tmp/o 2>&1' '^1\.[0-9]+\.[0-9]+' ;;
		Firefox) run Firefox '/opt/app.AppImage --version </dev/null >/tmp/o 2>&1' 'Mozilla Firefox [0-9]' ;;
		claude) run claude '/opt/app.AppImage --version </dev/null >/tmp/o 2>&1' '[0-9]+\.[0-9]+\.[0-9]+ \(Claude Code\)' ;;
		Pinta) run Pinta '/opt/app.AppImage --version </dev/null >/tmp/o 2>&1' '^3\.1' ;;
		esac
		if [ $? = 0 ]; then r=PASS; else r=FAIL; fail=1; fi
		echo "$k $t $r $((SECONDS - s))s"
	done
done
exit $fail
