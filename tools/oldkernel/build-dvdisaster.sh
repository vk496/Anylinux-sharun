#!/usr/bin/env bash
# Build the dvdisaster AppImage from speed47/dvdisaster PR #219 (quick-sharun
# based) with THIS checkout's sharun, the way that PR's release job does:
# Ubuntu 24.04 container, pinned quick-sharun, contrib/anylinux/*.sh.
#   build-dvdisaster.sh [git-url [ref]]     default: vk496/dvdisaster appimage-anylinux
# Result: cache/appimages/dvdisaster-*-x86_64.AppImage
set -eu
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../.." && pwd); c=$here/cache
url=${1:-https://github.com/vk496/dvdisaster.git}; ref=${2:-appimage-anylinux}
UBUNTU=ubuntu:24.04@sha256:9c7f200c07e3d4a03e7249d2c16bf66a51120fb876aa2242cf31451412543289
QS=https://raw.githubusercontent.com/pkgforge-dev/Anylinux-AppImages/7b737cc0d6d9b9a061e3073285e809aac1f91fdf/useful-tools/quick-sharun.sh
QS_SHA=93644e152bda61b3f02067dbf26e91d34996b63d6ad8c55ea7eb0534922f8a45
. "$here/helper-tar.sh"
helper_tar_serve

src=$c/dvdisaster-src
if [ -d "$src/.git" ]; then git -C "$src" fetch -q origin "$ref" && git -C "$src" checkout -q -f FETCH_HEAD
else git clone -q "$url" "$src" && git -C "$src" checkout -q "origin/$ref"; fi
[ -s "$c/quick-sharun" ] || curl -fsSL -o "$c/quick-sharun" "$QS"
echo "$QS_SHA  $c/quick-sharun" | sha256sum -c -
chmod 755 "$c/quick-sharun"

docker run --rm --network host --privileged "${HELPER_TAR_ENV[@]}" \
	-v "$src:/dvdisaster" -v "$c/quick-sharun:/usr/local/bin/quick-sharun:ro" -w /dvdisaster \
	"$UBUNTU" sh -c 'rc=0; { apt-get update -qq && apt-get install -y -qq --no-install-recommends ca-certificates curl \
		&& sh contrib/anylinux/get-dependencies.sh && sh contrib/anylinux/make-appimage.sh; } || rc=$?
		chown -R '"$(id -u):$(id -g)"' /dvdisaster; exit $rc'
mkdir -p "$c/appimages"; cp -v "$src"/dist/dvdisaster*.AppImage "$c/appimages/"
