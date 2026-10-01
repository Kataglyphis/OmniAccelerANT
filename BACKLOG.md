# Backlog

Follows the protocol ANTfrastructure's agentic loop (`shared/agentic-loop/`)
consumes, so the loop this repo adopted on 2026-09-13 (`scripts/agentic-loop/`,
§ *Agentic loop* below) reads it unchanged.

## Protocol

- `- [ ]` actionable — the planner may pick it up
- `- [b]` blocked — skipped, and excluded from the pending count, so a
  backlog containing only blocked items still lets the planner run again
- `- [x]` completed — pruned on sight; the history lives in git

## Open — Windows arm64

- [ ] **What the Windows arm64 lane does not prove yet** [M, ★]. The lane went green
      on 2026-09-27 (run 36322839058). It went red on 2026-09-29, when windows-11-arm
      moved to VS 2026 and MSVC's `cl` stopped at STL1011. Since then the app builds with
      clang-cl (test run 36622834879). On the windows-11-arm device the app tree passes
      the hub's import walk (40 files, 0 unresolved), and the app stays up 20 s at 147 MB
      with a real window. No camera frame and no inference have run on arm64 (the
      runner has no camera), no arm64 MSIX is built, and the integration test does not
      run there (`flutter test -d windows` builds with MSVC, which STL1011 stops). The
      lane's tests gate since run 36906197668 (AGENTS.md § 5, *What each lane tests*).

## Open — Linux Rust webcam inference (landed 2026-09-16, artifacts closed 2026-09-17)

The lane builds the crate with `gstreamer,onnxruntime_dynamic`, the packaged
artifacts carry their GStreamer/ONNX Runtime/model closure, `$ORIGIN` rpaths make
them load on a target, and both headless bundle gates run before packaging. One
thing is still unproven.

- [b] **No frame has travelled Rust → `knt_push_frame` → texture.** Blocked on
      hardware, not on code: frames end in a GTK texture, and the native lane's
      Xvfb (launch smoke and integration test, since 2026-10-01) has no camera
      behind it. The dev box is Windows with a C920 and `usbipd` installed, so
      the route exists (§ 4) — attach the camera to WSL, run the bundle under
      Xvfb in the image, and grep the log for
      `[my_texture] first pushed frame`. `xvfb-run` is in the image since
      `:latest` of 2026-09-29 (hub CON20, checked in the published amd64 child).

## Open — smaller code leftovers

- [ ] **`books/` and `games/` markdown are missing**, ratcheted in
      `test/settings_asset_paths_test.dart`'s `_knownMissing`. Every `/books/*`
      and `/games/*` route renders a failed load on the deployed web build.
      Equivalents exist under `dummy_assets/`, so this is a content decision,
      not a recovery problem. Shrink the ratchet set; never grow it.

## Open — duplication and drift

- [ ] `run-native-linux.sh` / `run-android.sh` read as host-side scripts but are
      what the CI lane actually invokes — the naming still misleads. The rule
      they sit beside holds without exception: **`scripts/linux/lib/` holds only
      files that are sourced or imported, never a file you invoke.**

## Open — release and repository state

- [ ] **`main` is 388 commits behind `develop`** (counted 2026-10-01; 246 when
      this was written), last synced by PR #23. Decide
      what `main` is for. If it is the release branch, that gap is the finding;
      if nothing reads it, say so in a doc and stop carrying it. Nothing in
      `.github/workflows/` triggers on `main` alone any more, so today it costs
      nothing but confuses every reader.
- [ ] **Branch protection after the develop-default rollout (2026-09-16).**
      `develop` is now the default in all 11 active non-fork Kataglyphis repos.
      Protection is per-branch, so whatever guarded `main` in the seven that
      were switched does not guard `develop`. **Verified 2026-09-17: this repo
      has no protection at all** — `gh api
      repos/Kataglyphis/OmniAccelerANT/branches/{develop,main}/protection`
      returns `404 Branch not protected` for both — still true on 2026-09-25.
      `web.yml` has since stopped claiming its job name "is the
      required-status-check string on develop's branch protection": its comment
      now says the name *was* that string and points back here. Either
      set protection (owner action — deciding what to require is the whole
      point) or stop referencing it.

## Open — verification gaps

- [ ] **G6 over the Pi producer bundle has not run since the hub pin moved past
      e72a9a37.** `scripts/linux/cat-stream/package-producer-bundle.sh` proves
      `/bin/kataglyphis_cat_webrtc`, which carries the chain ORT's Linux source
      path as a string, with this repo's hub. Re-run it with the next Pi bundle.
      (The Windows half is done: windows-x64 run 36154744287 had the real
      `oxidant.dll` in the runner when G6 passed.)
- [ ] `scripts/windows/Start-Windows.ps1` now launches (2026-09-17) but the
      window cannot be seen from the agent's shell: it runs in **Session 0**,
      where ANGLE/DXGI surface creation fails (`SwapChain11 … 0x887A0022`,
      `EGL Error: Context Lost`) and there is no desktop. The engine, the Rust
      bridge and the frb version check all pass there — the residual is "no
      interactive desktop", not an app defect. Confirm on the console session.
- [ ] **The Windows container's sync-back plants unusable reparse points in
      the host tree.** Robocopy of the container's cargo cache into
      `third_party/OxidANT/target` writes Linux-style links as Windows reparse
      points with no readable target (found on
      `cxxbridge/rust/cxx.h`), and bsdtar then aborts the next inbound
      transfer with `Cannot stat: Invalid argument` — the build started with
      no scripts at all. Mitigated 2026-09-17 by excluding that path from
      `Build-Windows-Container.ps1`'s inbound stream (the container builds
      into its own `rust_target`); upstream's sync-back still writes them.
- [ ] **Two of the Windows lane checks added on 2026-09-28 have not run on a Windows
      host with an image.** (*Flutter AOT Freshness* has: windows-x64 run 36866007231,
      2026-10-01, `[OK] Flutter AOT Freshness` on the Release runner.) The lane guard's
      `docker top` reading
      (`Test-WindowsBuildActive`) has only seen fixtures, since the dev box held
      no Windows image; and the scoped `-CodeQL` run is manual-only. Confirm
      each the first time it runs.

## Agentic loop

Adopted 2026-09-13: `scripts/agentic-loop/` (config, runner wrappers, prompt
overlays); engine opencode **v2**, executor model `opencode-go/deepseek-v4.1-flash`. Windows builds go
through `scripts/windows/Build-Windows-Container.ps1`. Run commands and rules:
AGENTS.md § 5.
