# Backlog

Follows the protocol ANTfrastructure's agentic loop (`shared/agentic-loop/`)
consumes, so the loop this repo adopted on 2026-09-13 (`scripts/agentic-loop/`,
§ *Agentic loop* below) reads it unchanged.

## Protocol

- `- [ ]` actionable — the planner may pick it up
- `- [b]` blocked — skipped, and excluded from the pending count, so a
  backlog containing only blocked items still lets the planner run again
- `- [x]` completed — pruned on sight; the history lives in git

## Open — correctness

- [ ] **The flatpak has no camera access.** The pinned hub's
      `app_packaging_flatpak_finish_args_block` appends
      `KATAGLYPHIS_FLATPAK_FINISH_ARGS` (space-separated) to its four defaults,
      whose only device is `--device=dri`, so a sandboxed install cannot open a
      webcam even though the GStreamer closure and the model travel inside it.
      Flatpak has no `--device=video`; the hub's comment names `--device=all`
      for a camera. Nothing in this repo sets the variable yet. (The runner
      rpath half was fixed on 2026-09-17: `$ORIGIN/lib:$ORIGIN/../lib` in
      `bundle-runtime-closure.sh`.)

## Open — Windows arm64

- [ ] **What the Windows arm64 lane does not prove yet** [M, ★]. The lane went green
      on 2026-09-27 (run 36322839058). It went red on 2026-09-29, when windows-11-arm
      moved to VS 2026 and MSVC's `cl` stopped at STL1011. Since then the app builds with
      clang-cl (test run 36622834879). On the windows-11-arm device the app tree passes
      the hub's import walk (40 files, 0 unresolved), and the app stays up 20 s at 147 MB
      with a real window. No camera frame and no inference have run on arm64 (the
      runner has no camera), and no arm64 MSIX is built. The lane is described in
      `windows-arm64.yml` and in AGENTS.md § 5.

## Open — Linux Rust webcam inference (landed 2026-09-16, artifacts closed 2026-09-17)

The lane builds the crate with `gstreamer,onnxruntime_dynamic`, the packaged
artifacts carry their GStreamer/ONNX Runtime/model closure, `$ORIGIN` rpaths make
them load on a target, and both headless bundle gates run before packaging. One
thing is still unproven.

- [b] **No frame has travelled Rust → `knt_push_frame` → texture.** Blocked on
      hardware, not on code: frames end in a GTK texture and no lane has a
      `DISPLAY`. The dev box is Windows with a C920 and `usbipd` installed, so
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
- [ ] **Delete `export_android_gstreamer_env`** (`scripts/linux/lib/container-steps.sh`,
      called from `ci-container-run-android.sh`). It only existed because the image
      shipped the Android GStreamer SDK without exporting `GSTREAMER_ROOT_ANDROID`.
      The blocker is cleared: the pinned hub's `linux/Dockerfile.package` sets
      `ENV GSTREAMER_ROOT_ANDROID=/opt/android/gstreamer`, and android run
      36154744222 printed no line from the function while the APK built. Remove it
      together with the bullet that describes it (AGENTS.md § 4), and prove it with
      the android lane.

## Open — release and repository state

- [ ] **`main` is 329 commits behind `develop`** (counted 2026-09-25; 246 when
      this was written), last synced by PR #23. Decide
      what `main` is for. If it is the release branch, that gap is the finding;
      if nothing reads it, say so in a doc and stop carrying it. Nothing in
      `.github/workflows/` triggers on `main` alone any more, so today it costs
      nothing but confuses every reader.
- [ ] **`version:` is still `1.1.0+1`**, which is what the annotated tag
      `1.1.0+1` already names — 329 commits ago (2026-09-25). `app-packaging.sh` stamps it
      into the `.deb` `Version:`, the AppImage filename and the flatpak
      filename, so every artifact built since is version-indistinguishable from
      that release. `msix_config.msix_version` repeats it by hand at
      `pubspec.yaml`, so the two move together or drift.
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
- [ ] **The Linux artifacts each carry the 59 MB detector model** since
      2026-09-17 (`data/resources/models/yolov10m.onnx`, in tar/deb/AppImage/
      flatpak). That is the "works out of the box" choice;
      `KATAGLYPHIS_BUNDLE_MODEL=0` on the lane drops it for a smaller artifact
      that then needs `KATAGLYPHIS_ONNX_MODEL` at runtime. Decide if the default
      should flip.

## Open — the web lane's rustup step

- [ ] **Name the image's dated nightly instead of the floating `nightly`.**
      `ci-container-run-web-linux.sh` still runs `rustup toolchain install nightly
      --component rust-src --target wasm32-unknown-unknown`, guarded on the two
      components being absent. On the read-only image layer a floating-channel
      update dies with `Invalid cross-device link (os error 18)` (seen 2026-09-16),
      and since 2026-09-25 CI takes the install path on every run (web run
      36154744073 synced the channel and downloaded both, 8 s). The hub's
      `docs/consumer-image-contract.md` § *The web lane toolchain* documents the
      fix: the image installs `RUST_NIGHTLY_TOOLCHAIN` (`nightly-2026-06-28` in the
      pinned `versions.env`) with both components, and FRB's
      `--wasm-pack-rustup-toolchain` can name it.

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
- [ ] **The Windows lane checks added on 2026-09-28 have not run on a Windows
      host with an image.** *Flutter AOT Freshness* first runs in the next
      windows-x64 CI build; the lane guard's `docker top` reading
      (`Test-WindowsBuildActive`) has only seen fixtures, since the dev box held
      no Windows image; and the scoped `-CodeQL` run is manual-only. Confirm
      each the first time it runs.

## Agentic loop

Adopted 2026-09-13: `scripts/agentic-loop/` (config, runner wrappers, prompt
overlays); engine opencode **v2**, executor model `opencode-go/deepseek-v4.1-flash`. Windows builds go
through `scripts/windows/Build-Windows-Container.ps1`. Run commands and rules:
AGENTS.md § 5.
