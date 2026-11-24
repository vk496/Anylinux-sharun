#!/usr/bin/env bash
# Rebuild the AppImages in cache/appimages with another runtime, to try a runtime
# change without rebuilding the applications.
#   repack-runtime.sh <uruntime-binary> [outdir]   (default outdir: cache/appimages-newrt)
# SHARUN=<sharun-binary> also replaces every copy of the sharun inside the AppDirs (AppRun,
# bin/*), to try a sharun release without rebuilding the applications.
# Needs the AppImages to be extractable on the host (--appimage-extract) and
# appimagetool (downloaded once into cache/).
set -eu
here=$(cd "$(dirname "$0")" && pwd); c=$here/cache
rt=$(realpath "$1"); out=${2:-$c/appimages-newrt}
tool=$c/appimagetool
[ -x "$tool" ] || { curl -fsSL -o "$tool" https://github.com/pkgforge-dev/appimagetool/releases/download/0.7.1/appimagetool-full-x86_64-linux; chmod +x "$tool"; }
mkdir -p "$out"
for img in "$c"/appimages/*.AppImage; do
	n=$(basename "$img"); w=$(mktemp -d)
	( cd "$w" && cp "$img" in.AppImage && ./in.AppImage --appimage-extract >/dev/null 2>&1 && mkdir o &&
	  if [ -n "${SHARUN:-}" ]; then
		old=$(sha256sum AppDir/sharun | cut -d' ' -f1)
		find AppDir -type f -size "$(stat -c%s AppDir/sharun)c" | while read -r f; do
			[ "$(sha256sum "$f" | cut -d' ' -f1)" = "$old" ] && cat "$SHARUN" >"$f"
		done
	  fi &&
	  "$tool" AppDir --runtime "$rt" -o o -n "${n%.AppImage}" >/dev/null 2>&1 ) || { echo "skip $n" >&2; rm -rf "$w"; continue; }
	mv "$w/o/${n%.AppImage}" "$out/$n"; chmod +x "$out/$n"; rm -rf "$w"; echo "repacked $n"
done
