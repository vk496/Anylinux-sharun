#!/usr/bin/env bash
# Download prebuilt legacy kernels + a static busybox into ./cache (no kernel builds).
# Usage: fetch.sh [kernel-id ...]   (default: 2.6.17)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
cache=$here/cache
mkdir -p "$cache"

UBU=http://old-releases.ubuntu.com/ubuntu/pool/main/l/linux-source-2.6.17
ALPINE_BASE=https://dl-cdn.alpinelinux.org/alpine/latest-stable
ALPINE=$ALPINE_BASE/main/x86_64

dl() { [ -s "$2" ] || { echo "fetch $1"; curl -fL --retry 3 -o "$2.part" "$1" && mv "$2.part" "$2"; }; }

# Extract a .deb's data.tar.* without needing dpkg.
unpack_deb() { # deb outdir
	d=$(mktemp -d); (cd "$d" && ar x "$1" && tar -xf data.tar.* -C "$2"); rm -rf "$d"
}

fetch_busybox() {
	[ -x "$cache/busybox" ] && return
	name=$(curl -fsL "$ALPINE/" | grep -o 'busybox-static-[0-9][^"]*\.apk' | head -1)
	dl "$ALPINE/$name" "$cache/$name"
	d=$(mktemp -d); tar -xzf "$cache/$name" -C "$d" 2>/dev/null || true
	install -m755 "$d/bin/busybox.static" "$cache/busybox"; rm -rf "$d"
}

# An Ubuntu amd64 generic kernel: only the vmlinuz is needed.
ubuntu_kernel() { # version deb pool-dir
	out=$cache/kernels/$1; mkdir -p "$out"
	[ -s "$out/vmlinuz" ] && return
	dl "http://old-releases.ubuntu.com/ubuntu/pool/main/l/$3/$2" "$cache/$2"
	t=$(mktemp -d); unpack_deb "$cache/$2" "$t"
	cp "$t"/boot/vmlinuz-* "$out/vmlinuz"; rm -rf "$t"
}

fetch_kernel() {
	case $1 in
	2.6.17) # Ubuntu 6.10 "Edgy" amd64: the vanilla 2.6.17 base this project targets
		deb=linux-image-2.6.17-10-generic_2.6.17-10.33_amd64.deb
		out=$cache/kernels/2.6.17; mkdir -p "$out"
		[ -s "$out/vmlinuz" ] && return
		dl "$UBU/$deb" "$cache/$deb"
		t=$(mktemp -d); unpack_deb "$cache/$deb" "$t"
		cp "$t"/boot/vmlinuz-* "$out/vmlinuz"; rm -rf "$t" ;;
	2.6.16) # Debian linux-2.6.16-18 amd64 (snapshot.debian.org, by content hash)
		deb=linux-image-2.6.16-2-amd64-generic_2.6.16-18_amd64.deb
		out=$cache/kernels/2.6.16; mkdir -p "$out"
		[ -s "$out/vmlinuz" ] && return
		dl "https://snapshot.debian.org/file/97ac24835a46c79521accc7ba6af7c5d5068cfc7" "$cache/$deb"
		t=$(mktemp -d); unpack_deb "$cache/$deb" "$t"
		cp "$t"/boot/vmlinuz-* "$out/vmlinuz"; rm -rf "$t" ;;
	2.6.15) # Ubuntu 6.06 "Dapper" amd64: the first release, before the *at syscalls (2.6.16)
		deb=linux-image-2.6.15-23-amd64-generic_2.6.15-23.39_amd64.deb
		out=$cache/kernels/2.6.15; mkdir -p "$out"
		[ -s "$out/vmlinuz" ] && return
		dl "http://old-releases.ubuntu.com/ubuntu/pool/main/l/linux-source-2.6.15/$deb" "$cache/$deb"
		t=$(mktemp -d); unpack_deb "$cache/$deb" "$t"
		cp "$t"/boot/vmlinuz-* "$out/vmlinuz"; rm -rf "$t" ;;
	2.6.12) # Ubuntu 5.10 "Breezy" amd64
		deb=linux-image-2.6.12-10-amd64-generic_2.6.12-10.45_amd64.deb
		out=$cache/kernels/2.6.12; mkdir -p "$out"
		[ -s "$out/vmlinuz" ] && return
		dl "http://old-releases.ubuntu.com/ubuntu/pool/main/l/linux-source-2.6.12/$deb" "$cache/$deb"
		t=$(mktemp -d); unpack_deb "$cache/$deb" "$t"
		cp "$t"/boot/vmlinuz-* "$out/vmlinuz"
		# UNIX sockets are a module on this kernel, not built in: run.sh loads it
		cp "$t"/lib/modules/*/kernel/net/unix/unix.ko "$out/unix.ko"; rm -rf "$t" ;;
	2.6.10) # Ubuntu 5.04 "Hoary" amd64: the kernel mhx/dwarfs#385 was reported on
		deb=linux-image-2.6.10-5-amd64-generic_2.6.10-34.7_amd64.deb
		out=$cache/kernels/2.6.10; mkdir -p "$out"
		[ -s "$out/vmlinuz" ] && return
		dl "http://old-releases.ubuntu.com/ubuntu/pool/main/l/linux-source-2.6.10/$deb" "$cache/$deb"
		t=$(mktemp -d); unpack_deb "$cache/$deb" "$t"
		cp "$t"/boot/vmlinuz-* "$out/vmlinuz"
		# UNIX sockets are a module on this kernel, not built in: run.sh loads it
		cp "$t"/lib/modules/*/kernel/net/unix/unix.ko "$out/unix.ko"; rm -rf "$t" ;;
	2.6.24) # Ubuntu 8.04 "Hardy" amd64
		deb=linux-image-2.6.24-32-generic_2.6.24-32.107_amd64.deb
		out=$cache/kernels/2.6.24; mkdir -p "$out"
		[ -s "$out/vmlinuz" ] && return
		dl "http://old-releases.ubuntu.com/ubuntu/pool/main/l/linux/$deb" "$cache/$deb"
		t=$(mktemp -d); unpack_deb "$cache/$deb" "$t"
		cp "$t"/boot/vmlinuz-* "$out/vmlinuz"; rm -rf "$t" ;;
	2.6.32) # Ubuntu 10.04 "Lucid" amd64
		deb=linux-image-2.6.32-74-generic_2.6.32-74.142_amd64.deb
		out=$cache/kernels/2.6.32; mkdir -p "$out"
		[ -s "$out/vmlinuz" ] && return
		dl "http://old-releases.ubuntu.com/ubuntu/pool/main/l/linux/$deb" "$cache/$deb"
		t=$(mktemp -d); unpack_deb "$cache/$deb" "$t"
		cp "$t"/boot/vmlinuz-* "$out/vmlinuz"; rm -rf "$t" ;;
	2.6.20) ubuntu_kernel 2.6.20 linux-image-2.6.20-17-generic_2.6.20-17.39_amd64.deb linux-source-2.6.20 ;; # 7.04 "Feisty"
	2.6.22) ubuntu_kernel 2.6.22 linux-image-2.6.22-16-generic_2.6.22-16.62_amd64.deb linux-source-2.6.22 ;; # 7.10 "Gutsy"
	2.6.27) ubuntu_kernel 2.6.27 linux-image-2.6.27-9-generic_2.6.27-9.19_amd64.deb linux ;; # 8.10 "Intrepid"
	2.6.28) ubuntu_kernel 2.6.28 linux-image-2.6.28-19-generic_2.6.28-19.66_amd64.deb linux ;; # 9.04 "Jaunty"
	2.6.35) ubuntu_kernel 2.6.35 linux-image-2.6.35-32-generic_2.6.35-32.68_amd64.deb linux ;; # 10.10 "Maverick"
	2.6.38) ubuntu_kernel 2.6.38 linux-image-2.6.38-9-generic_2.6.38-9.43_amd64.deb linux ;; # 11.04 "Natty"
	*) echo "unknown kernel '$1' (add it to fetch_kernel)" >&2; exit 1 ;;
	esac
}

# zig is only needed to build sharun/libs like CI does (build-*.sh).
fetch_zig() {
	[ -x "$cache/zig/zig" ] && return
	mkdir -p "$cache/zig"
	dl https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz "$cache/zig/zig.tar.xz"
	echo "70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00  $cache/zig/zig.tar.xz" | sha256sum -c -
	tar xJf "$cache/zig/zig.tar.xz" -C "$cache/zig" --strip-components=1
}

# Extra guest files copied over the initramfs by run.sh: strace (and its musl
# libs) for debugging, and a font so GUI screenshots show text.
fetch_overlay() {
	[ -d "$cache/overlay/usr/share/fonts" ] && [ -x "$cache/overlay/usr/bin/strace" ] && return
	mkdir -p "$cache/overlay" "$cache/dl"
	for repo in main community; do
		idx=$(curl -fsSL "$ALPINE_BASE/$repo/x86_64/")
		for p in strace musl libdw libelf libbz2 zlib zstd-libs xz-libs libgcc libeconf musl-fts musl-obstack argp-standalone libcap font-dejavu; do
			n=$(echo "$idx" | grep -o "href=\"$p-[0-9][^\"]*\\.apk\"" | head -1 | cut -d'"' -f2) || true
			[ -n "$n" ] || continue
			dl "$ALPINE_BASE/$repo/x86_64/$n" "$cache/dl/$n" && tar -xzf "$cache/dl/$n" -C "$cache/overlay" 2>/dev/null
		done
	done
	rm -f "$cache"/overlay/.PKGINFO "$cache"/overlay/.SIGN*
}

fetch_busybox
fetch_zig
fetch_overlay
for k in "${@:-2.6.17}"; do fetch_kernel "$k"; done
echo "ok: $cache"
