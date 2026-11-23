#!/usr/bin/env bash
# Boot a legacy kernel in QEMU with a tiny busybox initramfs and run a command.
#
#   run.sh [-k KERNEL] [-m MEM] [-t SECS] [-s] [-f FILE[:DEST]]... [-- CMD...]
#
#   -k  kernel id under cache/kernels (default 2.6.17)
#   -f  file/dir copied into the guest at /opt/<basename> (or /opt/DEST); repeatable
#   -C  QEMU -cpu model (default qemu64; `max` exposes AVX2 etc. even under TCG, `host` needs KVM)
#   -T  run the whole command under sharun's compat tracer (default on for kernels
#       older than 2.6.16: without it not even the AppImage runtime can start there)
#   -s  interactive shell on the serial console instead of running CMD
#   -t  timeout in seconds (default 120)
# CMD runs inside the guest via `sh -c` (cwd /opt); the script exits with its status.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
kernel=2.6.17 mem=512 tmo=120 shell=0 cpu=qemu64 trace=auto files=()
while getopts k:m:t:f:C:sT o; do
	case $o in
	k) kernel=$OPTARG ;; C) cpu=$OPTARG ;; m) mem=$OPTARG ;; t) tmo=$OPTARG ;; s) shell=1 ;; T) trace=1 ;; f) files+=("$OPTARG") ;;
	*) sed -n '2,12p' "$0"; exit 2 ;;
	esac
done
shift $((OPTIND - 1)); [ "${1:-}" = "--" ] && shift
cmd=$*

vmlinuz=$here/cache/kernels/$kernel/vmlinuz
[ -f "$vmlinuz" ] && [ -x "$here/cache/busybox" ] || "$here/fetch.sh" "$kernel"

root=$(mktemp -d); trap 'rm -rf "$root"' EXIT
mkdir -p "$root"/{bin,sbin,proc,sys,dev,tmp,opt,etc,root,usr/bin}
cp "$here/cache/busybox" "$root/bin/busybox"
for a in $("$root/bin/busybox" --list); do ln -sf busybox "$root/bin/$a"; done
[ -d "$here/cache/overlay" ] && cp -a "$here/cache/overlay/." "$root/"
printf 'root:x:0:0:root:/root:/bin/sh\n' >"$root/etc/passwd"
for f in "${files[@]}"; do
	src=${f%%:*}; dst=opt/$(basename "$src"); [ "$f" != "$src" ] && dst=opt/${f#*:}
	mkdir -p "$root/$(dirname "$dst")"; cp -a "$src" "$root/$dst"
done
printf '%s\n' "$cmd" >"$root/cmd"

# Kernels without the *at syscalls (< 2.6.16): everything, the AppImage runtime
# included, has to run inside the tracer that translates them.
if [ "$trace" = auto ]; then
	trace=0; [ "$kernel" != 2.6.16 ] && [ "$(printf '%s\n' "$kernel" 2.6.16 | sort -V | head -1)" = "$kernel" ] && trace=1
fi
if [ "$trace" = 1 ]; then
	sharun=${SHARUN:-$here/../../target/x86_64-unknown-linux-musl/release/sharun}
	[ -x "$sharun" ] || "$here/build-sharun.sh" >/dev/null
	mkdir -p "$root/opt/.trace"; cp "$sharun" "$root/opt/.trace/sharun"; ln "$root/opt/.trace/sharun" "$root/opt/.trace/AppRun"
	printf '#!/bin/sh\nexec "$@"\n' >"$root/opt/.trace/AppRun.sh"
fi

cat >"$root/init" <<'INIT'
#!/bin/busybox sh
/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t sysfs sys /sys 2>/dev/null
/bin/busybox mount -t tmpfs tmp /tmp
[ -c /dev/console ] || /bin/busybox mknod /dev/console c 5 1 2>/dev/null
[ -c /dev/null ] || /bin/busybox mknod -m666 /dev/null c 1 3 2>/dev/null
[ -c /dev/urandom ] || /bin/busybox mknod -m666 /dev/urandom c 1 9 2>/dev/null
[ -c /dev/zero ] || /bin/busybox mknod -m666 /dev/zero c 1 5 2>/dev/null
/bin/busybox mkdir -p /dev/pts && /bin/busybox mount -t devpts devpts /dev/pts 2>/dev/null
export PATH=/bin:/sbin:/usr/bin HOME=/root
echo "== guest kernel: $(uname -sr) $(uname -m)"
cd /opt
if grep -q 'oldkernel.shell=1' /proc/cmdline; then
	setsid sh -c 'exec sh </dev/console >/dev/console 2>&1'
	rc=0
else
	if [ -x /opt/.trace/AppRun ]; then /opt/.trace/AppRun sh -c "$(cat /cmd)"; rc=$?
	else sh -c "$(cat /cmd)"; rc=$?; fi
fi
echo "== guest exit: $rc"
echo o >/proc/sysrq-trigger 2>/dev/null; reboot -f
INIT
chmod +x "$root/init"
(cd "$root" && find . | cpio -o -H newc --quiet | gzip -1) >"$root/../initramfs.$$.gz"
trap 'rm -rf "$root" "$root/../initramfs.$$.gz"' EXIT

accel=tcg; [ -w /dev/kvm ] && accel=kvm
append="console=ttyS0 panic=-1 quiet oldkernel.shell=$shell"
# pc-i440fx-6.2, not "pc": newer machine types add an e820 range that 2.6.15 cannot handle
qargs=(-machine "pc-i440fx-6.2,accel=$accel" -cpu "$cpu" -m "$mem" -nographic -no-reboot
	-kernel "$vmlinuz" -initrd "$root/../initramfs.$$.gz" -append "$append"
	-serial mon:stdio -net none)
log=$(mktemp)
if [ $shell = 1 ]; then exec qemu-system-x86_64 "${qargs[@]}"; fi
set +e; timeout "$tmo" qemu-system-x86_64 "${qargs[@]}" </dev/null | tee "$log"; set -e
rc=$(sed -n 's/^== guest exit: \([0-9]*\).*/\1/p' "$log" | tail -1); rm -f "$log"
[ -n "$rc" ] || { echo "guest did not report an exit status (boot failure or timeout)" >&2; exit 125; }
exit "$rc"
