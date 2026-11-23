# Handover: AppImages on kernels < 2.6.16 (as of 2026-11-23, late)

## Goal
One AppImage, run directly (`./app.AppImage`) on any old 2.6 kernel (down to 2.6.15), no user tricks,
behaving like on current kernels. Forks/PRs where needed, minimal, **no Claude co-author lines**
(no "Generated with" line either).

## State of the pieces
| Piece | Where | Status |
|---|---|---|
| pipe2 flag fix | upstream PR #58 | **merged** 2026-11-23 (squash 964a17e). Review nits below |
| `*at` syscall translation (2.6.15) | upstream PR #59, fork branch `feat/at-syscalls-pre-2.6.16` (9845015, based on 964a17e) | open |
| `sharun --compat-exec CMD...` | upstream PR #60, fork branch `feat/compat-exec` (807de90, stacked on #59: review the last commit only) | open |
| Runtime relaunches itself under sharun | clone `/tmp/claude-1000/uruntime`, branch `compat-kernels-without-at` (64ce63b), pushed to fork `vk496/uruntime` | prototype, no PR yet (needs a sharun release, see below) |
| Test VM tooling | branch `oldkernel-test-vm` (this dir; 9 commits on top of dbdc139, contains the old pipe2 commit, needs a rebase onto main before it is tidy) | repack-runtime.sh, OLDKERNEL_TRACE/APPIMAGES env, `run.sh -N` |
| `wip/combined-test` | local throwaway in the main checkout, stale | do not push; build sharun from `/tmp/claude-1000/rb` (the rebased #59+#60 stack) instead |

Tested 2026-11-23 with sharun built from the rebased #59+#60 stack (`/tmp/claude-1000/rb`, zig as linker):
`run-tests.sh -k "2.6.15 2.6.16 2.6.17"` = 12/12 PASS (syscalls, coreutils, gtk2 GUI on Xvfb, dvdisaster).
Note that on kernels < 2.6.16 this battery wraps the whole guest command in the tracer (the AppImage
runtime is the old one). It does not prove that a plain `./app.AppImage` works: that is the newrt run below.
`--compat-exec` on 2.6.15, direct (`tools/oldkernel/test-compat-exec.sh <sharun> 2.6.15`): glibc bash+ls AppDir run;
the same bash without it dies with `Error 38`; no command prints usage, rc 1.

## PR #58 follow-up (maintainers' comments)
- Nemo-010 (bot review): approved as is, three nits for a follow-up, none blocking:
  1. `pipe2()` hardcodes `0x800`/`0x80000` (src/emulated_syscalls.rs, `PIPE_NONBLOCK`/`PIPE_CLOEXEC`); build the consts from `libc::O_NONBLOCK`/`O_CLOEXEC` like the steps that apply the flags.
  2. the fd readback in the `PlainPipe` completion duplicates `capture_pipe` and uses `unwrap_or_default()` (short slice would decode to fd 0 and fcntl stdin). Share one `pipe_ends()` helper with `.ok()?`.
  3. a sentence in the `translate_common` comment saying the emulation is unreachable in seccomp mode (filter mode 3.5, pipe2 2.6.27).
  Optional: for `O_DIRECT` still apply `FD_CLOEXEC` (one promise lost instead of two).
- Samueru-sama (maintainer): **new release planned 2026-11-24**, "if you find other bugs with kernel-compat feel free to PR those as well".
  => #59/#60 were opened right away to make that release. The follow-up nits are not done (small PR, only after #59/#60 settle to avoid conflicts in the same files).
- Same bug class still open: `epoll_create1` drops `EPOLL_CLOEXEC`.

## Runtime design (uruntime, VHSgunzo/uruntime)
The runtime's embedded `dwarfsextract` (libarchive) uses `openat`, so extraction fails on 2.6.15. Change:
x86_64-only embedded helper `sharun` (build_support.rs `SHARUN_VERSION`, checksums.txt, `Embed.sharun`);
in `main()` after the tool-name dispatch, `relaunch_without_at_syscalls` probes `openat`; if missing
(ENOSYS or returns its own number) it sets `URUNTIME_COMPAT_RELAUNCHED=1` and execs
`sharun --compat-exec <arg0> <args>` via `mfd_exec`. Tests counts 30->31 updated.
Build: `cd /tmp/claude-1000/uruntime; PATH=$HOME/.rustup/toolchains/nightly-x86_64-unknown-linux-gnu/lib/rustlib/x86_64-unknown-linux-gnu/bin:$PATH cargo --locked xtask appimage-dwarfs-x86_64`
(needs rust-src, llvm-tools, musl target on nightly; **do not** export the sharun build's RUSTFLAGS/linker vars).
The sharun for the build is seeded by hand in `assets-x86_64/sharun-3.9.0/sharun` with its sha256 in checksums.txt
(placeholder URL = 3.9.0 release, which lacks `--compat-exec`; needs a real sharun release before a PR can merge).
The seeded sharun is from the pre-fix stack: reseed it with the one from `/tmp/claude-1000/rb` (it has the
probe-sentinel fix from #60) and rerun `repack-runtime.sh` before testing again.

## Results (newrt AppImages = repacked with the new runtime, run with `OLDKERNEL_TRACE=0`)
`APPIMAGES=$PWD/cache/appimages-newrt OLDKERNEL_TRACE=0 ./run-tests.sh -k "2.6.15 2.6.16 2.6.17"`
(in tools/oldkernel; `target` is a symlink, currently -> `/tmp/claude-1000/rb/target`, a sharun build with pipe2+`*at`+compat-exec)
- Earlier run: 11/12 pass, including 2.6.15 syscalls, coreutils, dvdisaster, all of 2.6.16/17.
- Directly running xterm AppImage on 2.6.15: works.
- **OPEN BUG: 2.6.15 gtk2 GUI fails**: Xvfb AppImage started directly never creates /tmp/.X11-unix/X99
  (waited 240 s). Extraction completes, AppRun prints "ptrace unavailable" (expected: already traced; a tracee's
  children are auto-traced so PTRACE_TRACEME in the nested AppRun fails), then nothing.
  The same test passed when the whole guest command was wrapped in `AppRun` tracer (`run.sh -T`). Differences to chase:
  background launch `&` with redirected stdio under `--compat-exec`; env guard inheritance; Xvfb's xkbcomp symlink
  (`/usr/bin/xkbcomp` -> AppImage) re-entering the runtime; `supervise` behaviour for a non-AppRun root.
  Next step: boot guest, start Xvfb, after ~90 s inspect `/proc/*/status|wchan|syscall` (script was at /tmp/claude-1000/g.sh).

## Other open items
- Bun demo exits early on 2.6.16 (needs `-C Nehalem`), uninvestigated.
- Release ordering: sharun PRs (#59, #60) -> sharun release (tomorrow) -> uruntime PR (pin URL+hash of that release) -> appimagetool/quick-sharun pick up the runtime.
- Worktrees `/tmp/claude-1000/tv` (branch oldkernel-test-vm), `/tmp/claude-1000/rb` (feat/compat-exec) and the clone `/tmp/claude-1000/uruntime` live in /tmp.
  Everything committed is pushed to the fork (`vk496`); uncommitted edits there are lost on reboot.
