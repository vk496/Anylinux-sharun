#!/usr/bin/env bash
# Download prebuilt legacy kernels + a static busybox into ./cache (no kernel builds).
# Usage: fetch.sh [kernel-id ...]   (default: 2.6.17)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
cache=$here/cache
mkdir -p "$cache"

UBU=http://old-releases.ubuntu.com/ubuntu/pool/main/l/linux-source-2.6.17
ALPINE=https://dl-cdn.alpinelinux.org/alpine/latest-stable/main/x86_64

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
	*) echo "unknown kernel '$1' (add it to fetch_kernel)" >&2; exit 1 ;;
	esac
}

fetch_busybox
for k in "${@:-2.6.17}"; do fetch_kernel "$k"; done
echo "ok: $cache"
