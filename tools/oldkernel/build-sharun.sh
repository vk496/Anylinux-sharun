#!/usr/bin/env bash
# Build sharun the way CI does (zig as the linker) -> target/.../release/sharun
# Needs the zig from cache/zig (fetched once, see below) and the pinned nightly.
set -eu
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/../.." && pwd); c=$here/cache
if [ ! -x "$c/zig/zig" ]; then echo "no $c/zig/zig: unpack zig 0.16.0 (see .github/workflows/ci.yml ZIG_VERSION) there" >&2; exit 1; fi
printf '#!/bin/bash\nexec %s/zig/zig cc -target x86_64-linux-musl "$@"\n' "$c" >"$c/zigcc"; chmod +x "$c/zigcc"
export ZIG_GLOBAL_CACHE_DIR=$c/zig-cache ZIG_LOCAL_CACHE_DIR=$c/zig-cache
export CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER=$c/zigcc
export RUSTFLAGS="-C target-feature=+crt-static -C link-self-contained=no"
cd "$root" && cargo build --release --target x86_64-unknown-linux-musl
echo "$root/target/x86_64-unknown-linux-musl/release/sharun"
