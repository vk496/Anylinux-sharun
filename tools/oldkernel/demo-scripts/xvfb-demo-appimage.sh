#!/bin/sh
# Xvfb as an AppImage: lets the old-kernel guest run GUI AppImages headlessly.
set -eux

ARCH="$(uname -m)"
SHARUN="https://raw.githubusercontent.com/${GITHUB_REPOSITORY%/*}/${GITHUB_REPOSITORY#*/}/refs/heads/main/useful-tools/quick-sharun.sh"

export ICON=DUMMY
export DESKTOP=DUMMY
export OUTPATH=./dist
export OUTNAME=xvfb-demo-"$ARCH".AppImage
export MAIN_BIN=Xvfb

pacman -Syu --noconfirm base-devel patchelf wget xorg-server-xvfb xorg-xkbcomp xkeyboard-config xorg-xwd xorg-xdpyinfo

wget --retry-connrefused --tries=30 "$SHARUN" -O ./quick-sharun
chmod +x ./quick-sharun
./quick-sharun /usr/bin/Xvfb /usr/bin/xkbcomp /usr/bin/xwd /usr/bin/xdpyinfo /usr/share/X11/xkb
./quick-sharun --make-appimage
