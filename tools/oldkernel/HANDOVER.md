# Handover: AppImages on kernels < 2.6.16 (as of 2026-11-23)

## Goal
One AppImage, run directly (`./app.AppImage`) on any old 2.6 kernel (down to 2.6.15), no user tricks,
behaving like on current kernels. Forks/PRs where needed, minimal, **no Claude co-author lines**.

## State of the pieces
| Piece | Where | Status |
|---|---|---|
| pipe2 flag fix | fork `vk496/Anylinux-sharun` branch `fix/pipe2-keep-flags`, upstream PR #58 | done, open |
| `*at` syscall translation (2.6.15) | branch `feat/at-syscalls-pre-2.6.16` (pushed) | done; battery passes 2.6.15/16/17 when run under a tracer |
| `sharun --compat-exec CMD...` (run any cmd under tracer) | branch `feat/compat-exec` (local commit d639cf6, NOT pushed), stacked on the `*at` branch | done, works |
| Runtime relaunches itself under sharun | local clone `/tmp/claude-1000/uruntime`, branch `compat-kernels-without-at` (1 local commit, fork `vk496/uruntime` exists, remote `vk496`, NOT pushed) | prototype, see below |
| Test VM tooling | branch `oldkernel-test-vm` (this dir) | repack-runtime.sh, OLDKERNEL_TRACE/APPIMAGES env, `run.sh -N` |
| `wip/combined-test` | local throwaway: compat-exec + `*at` + pipe2 cherry-pick, used to build the sharun embedded in the runtime | do not push |

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

## Results (newrt AppImages = repacked with the new runtime, run with `OLDKERNEL_TRACE=0`)
`APPIMAGES=$PWD/cache/appimages-newrt OLDKERNEL_TRACE=0 ./run-tests.sh -k "2.6.15 2.6.16 2.6.17"`
(in tools/oldkernel; needs `target` symlink to a sharun build with pipe2+`*at`)
- 11/12 pass, including 2.6.15 syscalls, coreutils, dvdisaster, all of 2.6.16/17.
- Directly running xterm AppImage on 2.6.15: works.
- **OPEN BUG: 2.6.15 gtk2 GUI fails**: Xvfb AppImage started directly never creates /tmp/.X11-unix/X99
  (waited 240 s). Extraction completes, AppRun prints "ptrace unavailable" (expected: already traced), then nothing.
  The same test passed when the whole guest command was wrapped in `AppRun` tracer (`run.sh -T`). Differences to chase:
  background launch `&` with redirected stdio under `--compat-exec`; env guard inheritance; Xvfb's xkbcomp symlink
  (`/usr/bin/xkbcomp` -> AppImage) re-entering the runtime; `supervise` behaviour for a non-AppRun root.
  Next step: boot guest, start Xvfb, after ~90 s inspect `/proc/*/status|wchan|syscall` (script was at /tmp/claude-1000/g.sh).

## Other open items
- Bun demo exits early on 2.6.16 (needs `-C Nehalem`), uninvestigated.
- Nothing from `feat/compat-exec` / `*at` branch / uruntime has an upstream PR yet (user asked: open PRs where needed, minimal, replication info in PR body, no tooling in PR branches).
- Release ordering: sharun PRs -> sharun release -> uruntime PR (pin URL+hash) -> appimagetool/quick-sharun pick up runtime.
- Worktree `/tmp/claude-1000/tv` (branch oldkernel-test-vm) and `/tmp/claude-1000/uruntime` live in /tmp: commit/push before reboot.
