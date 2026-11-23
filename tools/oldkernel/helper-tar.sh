# Sourced by build-*.sh. Builds this checkout's sharun + helper libs into the
# tarball quick-sharun normally downloads (sharun+helper-libs-x86_64.tar) and
# serves it on 127.0.0.1:8765. Upstream 3.9.0 provides what is not built here
# (dash and stubs/). After sourcing:
#   helper_tar_serve                      builds the tar and starts the server
#   docker run ... "${HELPER_TAR_ENV[@]}" the env that points quick-sharun at it
# The server is stopped when the calling script exits.

helper_tar_serve() {
	local up=https://github.com/pkgforge-dev/Anylinux-sharun/releases/download/3.9.0/sharun+helper-libs-x86_64.tar
	local sharun=$root/target/x86_64-unknown-linux-musl/release/sharun
	[ -x "$sharun" ] || "$here/build-sharun.sh" >/dev/null
	export ZIG_GLOBAL_CACHE_DIR=$c/zig-cache ZIG_LOCAL_CACHE_DIR=$c/zig-cache
	make -C "$root/lib" CC="$c/zig/zig cc -target x86_64-linux-gnu.2.31" LDFLAGS=-s >/dev/null 2>&1

	mkdir -p "$c/demo-tar"
	[ -s "$c/demo-tar/upstream.tar" ] || curl -fsSL -o "$c/demo-tar/upstream.tar" "$up"
	rm -rf "$c/demo-tar/pkg" && mkdir "$c/demo-tar/pkg" && tar -xf "$c/demo-tar/upstream.tar" -C "$c/demo-tar/pkg"
	cp "$sharun" "$root"/lib/*.so "$c/demo-tar/pkg/"
	(cd "$c/demo-tar/pkg" && tar -cf ../sharun+helper-libs-x86_64.tar -- *)

	( cd "$c/demo-tar" && exec python3 -m http.server 8765 --bind 127.0.0.1 >/dev/null 2>&1 ) &
	trap 'kill $! 2>/dev/null' EXIT
	sleep 1
	HELPER_TAR_ENV=(-e SHARUN_LINK=http://127.0.0.1:8765/sharun+helper-libs-x86_64.tar -e SKIP_INTEGRITY_CHECKS=1)
}
