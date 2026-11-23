#!/usr/bin/env bash
# Build an Anylinux-AppImages demo (default: gtk2-demo-appimage) with THIS
# checkout's sharun + helper libs, in an Arch container, into cache/appimages/.
#   build-demo.sh [demo-script-name]        e.g. xterm-demo-appimage
# A script of that name in demo-scripts/ wins over the upstream one.
set -eu
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../.." && pwd); c=$here/cache
demo=${1:-gtk2-demo-appimage}
. "$here/helper-tar.sh"
helper_tar_serve

mkdir -p "$c/demo-scripts"
if [ -f "$here/demo-scripts/$demo.sh" ]; then cp "$here/demo-scripts/$demo.sh" "$c/demo-scripts/$demo.sh"
else gh api "repos/pkgforge-dev/Anylinux-AppImages/contents/useful-tools/demo/$demo.sh" --jq .content | base64 -d >"$c/demo-scripts/$demo.sh"; fi

out=$c/demo-out; rm -rf "$out"; mkdir -p "$out"
docker run --rm --network host --privileged \
	-e GITHUB_REPOSITORY=pkgforge-dev/Anylinux-AppImages "${HELPER_TAR_ENV[@]}" \
	-v "$c/demo-scripts/$demo.sh:/demo.sh:ro" -v "$out:/out" -w /out \
	archlinux:latest sh -c 'pacman -Sy --noconfirm archlinux-keyring >/dev/null; rc=0; sh -eux /demo.sh || rc=$?; chown -R '"$(id -u):$(id -g)"' /out; exit $rc'
mkdir -p "$c/appimages"; cp -v "$out"/dist/*.AppImage "$c/appimages/"
