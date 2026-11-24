#!/usr/bin/env bash
# Build a vanilla Linux 2.6.N x86_64 kernel for the guest, for the versions no distribution
# ships a usable prebuilt kernel for (2.6.0-2.6.3, 2.6.6, 2.6.7, 2.6.13, 2.6.14, 2.6.19).
#   build-kernel.sh N [N...]         e.g. build-kernel.sh 13 14 19
# Sources come from kernel.org. Each version is built with the compiler of its time, taken from the
# Debian archive and run in place (nothing is installed): gcc 3.3 + binutils 2.15 for 2.6.0-2.6.3,
# gcc 3.4 + binutils 2.15 for 2.6.4-2.6.7, gcc 4.1 + binutils 2.17 from 2.6.8 on, and GNU make 3.81,
# because the old Makefiles do not parse with a current make. The config is defconfig minus
# everything the guest does not need (see below), so the kernels are minimal and small.
#
# The sources are patched only as far as a current host or these compilers need to build them:
#   - old kconfig (mconf.c) and the host tools build with a current host gcc
#   - gcc 4 / recent gas reject a few declarations and asm forms in the x86_64 code of 2.6.0-2.6.7
#   - 2.6.0-2.6.3 only run /init from an initramfs after mounting a root device: it is started first
#     there, exactly as later kernels do, so that the same initramfs works for every kernel.
# Nothing in the syscall or ptrace code is touched.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
tc=$here/cache/toolchains build=$here/cache/kbuild
deb() { # deb <url>: download into toolchains/dl, unpack into toolchains/<root>
	local url=$1 root=$2 f=$tc/dl/$(basename "$1") w
	mkdir -p "$tc/dl" "$tc/$root"
	[ -s "$f" ] || python3 -I -c 'import sys,urllib.request; urllib.request.urlretrieve(sys.argv[1], sys.argv[2])' "$url" "$f"
	w=$(mktemp -d); (cd "$w" && ar x "$f" && tar -xf data.tar.* -C "$tc/$root"); rm -rf "$w"
}
wrap() { # wrap <name> <root> <gcc binary> <gcc -B dir>: wrappers that run the downloaded tools in place
	local name=$1 root=$tc/$2 gcc=$3 bdir=$4 w=$tc/wrap-$1 t
	[ -x "$w/gcc" ] && return
	mkdir -p "$w"
	for t in ld as ar nm objcopy objdump strip ranlib readelf; do
		printf '#!/bin/sh\nexport LD_LIBRARY_PATH=%s/usr/lib:%s/lib\nexec %s/usr/bin/%s "$@"\n' "$root" "$root" "$root" "$t" >"$w/$t"
	done
	printf '#!/bin/sh\nexport LD_LIBRARY_PATH=%s/usr/lib:%s/lib\nexec %s/usr/bin/%s -B%s/ -B%s/usr/bin/ "$@"\n' \
		"$root" "$root" "$root" "$gcc" "$root/$bdir" "$root" >"$w/gcc"
	chmod +x "$w"/*
}
toolchain() { # toolchain <N>: print the wrapper dir to use for 2.6.N
	local M=https://archive.debian.org/debian/pool/main M64=https://archive.debian.org/debian-amd64/pool/main
	if [ "$1" -le 3 ]; then
		if [ ! -e "$tc/sarge33/.done" ]; then deb $M64/b/binutils/binutils_2.15-6_amd64.deb sarge33; deb $M64/g/gcc-3.3/gcc-3.3_3.3.5-13_amd64.deb sarge33
			deb $M64/g/gcc-3.3/cpp-3.3_3.3.5-13_amd64.deb sarge33; deb $M64/g/gcc-3.3/gcc-3.3-base_3.3.5-13_amd64.deb sarge33
			deb $M64/g/gcc-3.4/libgcc1_3.4.3-13sarge1_amd64.deb sarge33; touch "$tc/sarge33/.done"
		fi >&2
		wrap sarge33 sarge33 x86_64-linux-gcc-3.3 usr/lib/gcc-lib/x86_64-linux/3.3.5 >&2
		echo "$tc/wrap-sarge33"
	elif [ "$1" -le 7 ]; then
		if [ ! -e "$tc/sarge34/.done" ]; then deb $M64/b/binutils/binutils_2.15-6_amd64.deb sarge34; deb $M64/g/gcc-3.4/gcc-3.4_3.4.3-13sarge1_amd64.deb sarge34
			deb $M64/g/gcc-3.4/cpp-3.4_3.4.3-13sarge1_amd64.deb sarge34; deb $M64/g/gcc-3.4/gcc-3.4-base_3.4.3-13sarge1_amd64.deb sarge34
			deb $M64/g/gcc-3.4/libgcc1_3.4.3-13sarge1_amd64.deb sarge34; touch "$tc/sarge34/.done"
		fi >&2
		wrap sarge34 sarge34 x86_64-linux-gcc-3.4 usr/lib/gcc/x86_64-linux/3.4.3 >&2
		echo "$tc/wrap-sarge34"
	else
		if [ ! -e "$tc/etch/.done" ]; then deb $M/b/binutils/binutils_2.17-3+etch1_amd64.deb etch; deb $M/g/gcc-4.1/gcc-4.1_4.1.2-25_amd64.deb etch
			deb $M/g/gcc-4.1/cpp-4.1_4.1.2-25_amd64.deb etch; deb $M/g/gcc-4.1/gcc-4.1-base_4.1.2-25_amd64.deb etch; touch "$tc/etch/.done"
		fi >&2
		wrap etch etch x86_64-linux-gnu-gcc-4.1 usr/lib/gcc/x86_64-linux-gnu/4.1 >&2
		echo "$tc/wrap-etch"
	fi
}
[ -x "$tc/make/usr/bin/make" ] || deb https://archive.debian.org/debian/pool/main/m/make-dfsg/make_3.81-5_amd64.deb make
MAKE=$tc/make/usr/bin/make

patch_tree() { # patch_tree <N>, in the kernel source directory
	local v=$1
	# old kconfig (2.6.0-2.6.7): mconf.c redeclares current_menu as static, which a current gcc rejects
	if [ "$v" -le 7 ] && [ -f scripts/kconfig/mconf.c ]; then sed -i 's/^static struct menu \*current_menu;//' scripts/kconfig/mconf.c; fi
	[ -e include/linux/compiler-gcc4.h ] || cp include/linux/compiler-gcc3.h include/linux/compiler-gcc4.h
	# the x86_64 code of 2.6.0-2.6.7 declares things in a way gcc 4 and recent gas refuse
	local f=include/asm-x86_64/processor.h c=include/asm-x86_64/calling.h
	if [ "$v" -le 7 ]; then
		# extern array of a struct that is defined further down: move the declaration to the end
		if grep -q '^extern struct tss_struct init_tss\[NR_CPUS\];' $f; then
			sed -i '/^extern struct tss_struct init_tss\[NR_CPUS\];/d' $f
			python3 -I - $f <<'PY'
import sys
p = sys.argv[1]; s = open(p).read(); i = s.rindex('#endif')
open(p, 'w').write(s[:i] + 'extern struct tss_struct init_tss[NR_CPUS];\n\n' + s[i:])
PY
		fi
		# the same two asm macros are defined in calling.h and entry.S: keep the entry.S copy
		if grep -q '^	.macro FAKE_STACK_FRAME' $c; then
			python3 -I - $c <<'PY'
import sys, re
p = sys.argv[1]; s = open(p).read()
for m in ('FAKE_STACK_FRAME', 'UNFAKE_STACK_FRAME'):
    s = re.sub(r'[ \t]*\.macro[ \t]+' + m + r'\b.*?\.endm[ \t]*\n', '', s, count=1, flags=re.S)
open(p, 'w').write(s)
PY
		fi
		# storing a segment register with an explicit l suffix is an operand error for recent gas
		grep -rlE 'movl %%(es|ds|fs|gs|ss)' arch/x86_64 include/asm-x86_64 kernel mm fs drivers 2>/dev/null |
			xargs -r sed -i -E 's/movl %%(es|ds|fs|gs|ss)/mov %%\1/g'
		# _stext is declared both as a char and as an array
		sed -i -E 's/^([[:space:]]*)extern char _stext;/\1extern char _stext[];/; s/extern char _stext, _etext;/extern char _stext[], _etext[];/' include/asm-x86_64/hw_irq.h
		sed -i -E 's/^extern char _stext;/extern char _stext[];/; s/&_stext/_stext/g' arch/x86_64/mm/init.c 2>/dev/null || true
	fi
	# 2.6.0-2.6.3 start /init from an initramfs only after mounting a root device: start it first, as later kernels do
	if [ "$v" -le 3 ] && ! grep -q 'execute_command = "/init"' init/main.c; then
		python3 -I - init/main.c <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
i = s.index('static int init(void * unused)'); j = s.index('\tprepare_namespace();', i)
s = s[:j] + '\tif (sys_access((const char __user *) "/init", 0) == 0)\n\t\texecute_command = "/init";\n\telse\n\t\tprepare_namespace();' + s[j + len('\tprepare_namespace();'):]
s = s.replace('static int init(void * unused)', 'extern asmlinkage long sys_access(const char __user *filename, int mode);\nstatic int init(void * unused)', 1)
open(p, 'w').write(s)
PY
	fi
}

for v in "$@"; do
	w=$(toolchain "$v")
	mkdir -p "$build/dl" "$build/$v"
	tb=$build/dl/linux-2.6.$v.tar.bz2
	[ -s "$tb" ] || python3 -I -c 'import sys,urllib.request; urllib.request.urlretrieve(sys.argv[1], sys.argv[2])' \
		"https://cdn.kernel.org/pub/linux/kernel/v2.6/linux-2.6.$v.tar.bz2" "$tb"
	rm -rf "$build/$v/linux-2.6.$v"; tar -xjf "$tb" -C "$build/$v"
	cd "$build/$v/linux-2.6.$v"
	patch_tree "$v"
	hostcc="gcc -fcommon -std=gnu89 -w -include limits.h"
	MK=("$MAKE" ARCH=x86_64 HOSTCC="$hostcc" CC="$w/gcc" LD="$w/ld" AS="$w/as" AR="$w/ar" NM="$w/nm"
		OBJCOPY="$w/objcopy" OBJDUMP="$w/objdump" STRIP="$w/strip" RANLIB="$w/ranlib" -j"$(nproc)")
	"${MK[@]}" defconfig >/dev/null 2>&1 || cp arch/x86_64/defconfig .config
	cfg() { sed -i "/^# CONFIG_$1 is not set/d;/^CONFIG_$1=/d" .config
		if [ "$2" = n ]; then echo "# CONFIG_$1 is not set" >>.config; else echo "CONFIG_$1=$2" >>.config; fi; }
	# the guest has a serial console, an initramfs and busybox: nothing else is needed
	for s in FUSION I2O IA32_EMULATION IA32_AOUT COMPAT MODULES IDE SCSI USB SOUND SATA ATA NETDEVICES WIRELESS \
		INPUT_JOYSTICK SERIO FB VGA_CONSOLE PCMCIA ISDN HOTPLUG_CPU CPU_FREQ SUSPEND PM KPROBES PROFILING DEBUG_KERNEL; do cfg $s n; done
	for s in BLK_DEV_INITRD SERIAL_8250 SERIAL_8250_CONSOLE UNIX PROC_FS SYSFS TMPFS DEVPTS_FS UNIX98_PTYS \
		MAGIC_SYSRQ SYSVIPC EPOLL FUTEX BINFMT_ELF PRINTK NET INET TTY; do cfg $s y; done
	yes "" | "${MK[@]}" oldconfig >/dev/null 2>&1 || true
	# the boot sector builder is a host program that has to see the kernel's boot.h, not the host's asm/boot.h
	"${MK[@]}" HOSTCC="$hostcc -Iinclude" bzImage >"$build/$v/build.log" 2>&1 ||
		{ tail -25 "$build/$v/build.log"; echo "build of 2.6.$v failed, full log: $build/$v/build.log" >&2; exit 1; }
	out=$here/cache/kernels/2.6.$v; mkdir -p "$out"; cp arch/x86_64/boot/bzImage "$out/vmlinuz"
	echo "built 2.6.$v: $(stat -c %s "$out/vmlinuz") bytes -> $out/vmlinuz"
done
