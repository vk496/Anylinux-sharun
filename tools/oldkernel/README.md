# Old-kernel test VM

Boots a real legacy kernel in QEMU so the old-kernel compatibility layer
(`src/kernel_compat.rs`, `src/emulated_syscalls.rs`) can be tested on the kernels
it targets. Nothing is built from kernel sources: prebuilt kernels are downloaded
and the guest is just busybox in an initramfs (boots in a few seconds, no disk,
no network).

| id | kernel | from |
|---|---|---|
| `2.6.17` | Ubuntu 6.10 `2.6.17-10.33` amd64 | old-releases.ubuntu.com |
| `2.6.16` | Debian `2.6.16-18` amd64 | snapshot.debian.org |

Needs `qemu-system-x86_64`, `cpio`, `musl-gcc`, `docker`, `gh` and `curl`; zig 0.16.0
unpacked in `cache/zig` (see `ZIG_VERSION` in the CI workflow) to build like CI does.
Everything downloaded lives in the git-ignored `cache/`.

## Use

```sh
tools/oldkernel/build-sharun.sh          # sharun, built like CI (zig as linker)
tools/oldkernel/run-tests.sh             # every test, on every kernel
tools/oldkernel/run.sh -k 2.6.16 -- 'uname -r'          # one command in the guest
tools/oldkernel/run.sh -s                                # shell on the serial console
```

`run.sh [-k KERNEL] [-m MEM] [-t SECS] [-C CPU] [-f FILE[:DEST]]... [-s] [-- CMD]`
copies files to `/opt` in the guest, runs `CMD` and exits with its status. `-C max`
exposes AVX2 etc. even without KVM. If `cache/overlay` exists (musl + `strace`) it is
copied into the guest. Under ptrace these kernels return an unimplemented syscall's
own number instead of `ENOSYS`, so inject it to see real behaviour
(`strace -e inject=execveat:error=ENOSYS ...`).

## Tests

| script | what it checks |
|---|---|
| `test-syscalls.sh <sharun> [kernel]` | tiny static programs (`tests/*.c`) through `AppRun`: the semantics of emulated syscalls (currently `pipe2` flags) |
| `test-sharun.sh <sharun> [kernel]` | host glibc programs (coreutils, bash) bundled in an AppDir and run via `AppRun` |
| `test-appimage.sh [-k K] [-d] <AppImage> [args]` | an AppImage run as a user would, no manual unpacking (the runtime extracts itself: there is no FUSE) |
| `test-gui.sh <xvfb.AppImage> <app.AppImage>` | GUI app against an Xvfb AppImage; saves a screenshot |
| `test-dvdisaster.sh` | dvdisaster (speed47/dvdisaster#219) RS03 create, test, damage, fix, checksum |

`build-demo.sh [name]` builds an Anylinux-AppImages demo (default `gtk2-demo-appimage`,
also `demo-scripts/xvfb-demo-appimage.sh`) and `build-dvdisaster.sh` the dvdisaster
AppImage, both in containers and both with **this checkout's** sharun and `lib/*.so`
swapped into the helper tarball `quick-sharun` downloads (`helper-tar.sh`).
