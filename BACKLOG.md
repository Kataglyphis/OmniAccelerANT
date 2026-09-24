# Backlog

Follows the protocol ANTfrastructure's agentic loop (`shared/agentic-loop/`)
consumes, so this file can be handed to it unchanged when the loop is adopted
here.

## Protocol

- `- [ ]` actionable — the planner may pick it up
- `- [b]` blocked — skipped, and excluded from the pending count, so a
  backlog containing only blocked items still lets the planner run again
- `- [x]` completed — pruned on sight; the history lives in git

## Open — correctness

- [b] **Move `third_party/ANTfrastructure` on to the hub's OrtGetApiBase-definition
      rule.** The pin, e72a9a37 (moved in c47f599), carries the fingerprint fix as
      1b9f492e: G6 reads `liboxidant.so` as an importer, and the liboxidant cases of
      `scripts/linux/tests/test-check-bundle-closure.sh` are back (17 of 17 in the
      image at e72a9a37). What the pin still lacks is the follow-up. With it, a file
      that DEFINES `OrtGetApiBase` counts as ORT under any name, so a renamed ORT
      with no fingerprint no longer passes as an importer beside the chain copy.
      This repo's packer gives exactly that `$ORIGIN` RUNPATH to such a file.
      - The hub branch is `fix/g6-ort-definition-rule`: 297c896e (docs), then
        f01b7cbf `fix(ort-census): an ORT under another name is found by the
        OrtGetApiBase it defines`. It fast-forwards from develop e72a9a37.
      - The same change was first made on `fix/g6-linux-bundle-oxidant` (960345ca,
        e2e12f02). That branch predates the integration, and a merge of it
        conflicts. Take the develop-based one.
      - Measured against it: both bundle-gate suites pass in the image, and so
        does the 2026-09-17 release bundle. `OrtRunner.Tests.ps1` passes 6 of 6,
        and the NUL-fixed OxidANT and AccelerANTgine suites 10 of 10 and 9 of 9.
        Nothing in this repo changes at that bump.
      - Blocked on the hub branch reaching the hub's remote (the submodule-pins
        workflow checks reachability), and on the paused Windows build, which
        uses this submodule checkout as its closure.
- [b] **OxidANT and AccelerANTgine: end the fake ORT source path in their
      Windows ORT suites with a NUL, before their hub pins pass 1b9f492e.**
      `OxidANT/scripts/windows/tests/OrtPayload.Tests.ps1` (lines 32 and 73) and
      `AccelerANTgine/scripts/windows/tests/OrtBundle.Tests.ps1` (lines 32 and
      71) write `"$chainSrc OrtGetApiBase"` and `"$chainSrc FileVersion 1.27.0"`.
      The whole-path census finds no fingerprint there, so one case in each
      turns `UNPROVEN` where it expects `STALE`. Measured on scratch copies:
      OxidANT 9 of 10, AccelerANTgine 8 of 9. `` "$chainSrc`0OrtGetApiBase" ``
      passes at a7ccc896, at the fix and with the definition rule (10 of 10 and
      9 of 9), so it can land first. Both still pin hub 57bec177. Blocked here:
      the edit belongs in those two repositories; this repo only moves their
      gitlinks afterwards.
- [ ] **The flatpak has no camera access and its runner path was only just
      fixed.** `app_packaging_package_linux_bundle_flatpak` writes
      `finish-args` with `--device=dri` but no `/dev/video*`, so a sandboxed
      flatpak install cannot open a webcam even though the GStreamer closure and
      the model now travel inside it. The runner-rpath half was fixed on
      2026-09-17 (`$ORIGIN/lib:$ORIGIN/../lib` in `bundle-runtime-closure.sh`,
      because flatpak installs the binary into `/app/bin` with the libs in
      `/app/lib`). The device half lives in ANTfrastructure's
      `app-packaging.sh`, so it needs an upstream change (or a
      `KATAGLYPHIS_FLATPAK_EXTRA_FINISH_ARGS`-style knob upstreamed first).

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
      `[my_texture] first pushed frame`. Needs `xvfb` in the image, or an
      `apt-get install` as root inside the container.

## Open — smaller code leftovers

- [ ] **`books/` and `games/` markdown are missing**, ratcheted in
      `test/settings_asset_paths_test.dart`'s `_knownMissing`. Every `/books/*`
      and `/games/*` route renders a failed load on the deployed web build.
      Equivalents exist under `dummy_assets/`, so this is a content decision,
      not a recovery problem. Shrink the ratchet set; never grow it.

## Open — duplication and drift

- [ ] `run-native-linux.sh` / `run-android.sh` read as host-side scripts but are
      what the CI lane actually invokes — the naming still misleads.
      (`scripts/linux/lib/check-linux.sh`, the other half of this entry, was
      deleted: it was a human entry point sitting in `lib/` with no caller, and
      the checks it ran are reached through `run-native-linux.sh` and the CI
      drivers anyway. `package-linux.sh` and `generate-docs.sh` were the last
      two executables in `lib/` and moved up to `scripts/linux/` on 2026-09-15,
      so the rule now holds without exception: **`scripts/linux/lib/` holds only
      files that are sourced or imported, never a file you invoke.**
      `dartdoc-guides-local.py`, the one non-`.sh` file that was left there, is
      gone too: ANTfrastructure upstreamed its three divergences on 2026-09-15
      and `generate-docs.sh` calls `dartdoc_build_main`.)
- [ ] **The lane guard is one-sided.** `Invoke-LinuxLane.ps1` refuses to start
      while another lane's container (`kataglyphis-linux-lane-*`) or the Windows
      build container (`omniaccelerant-agentic-build`) is up, but
      `Build-Windows.ps1` / `Build-Windows-Container.ps1` have no reciprocal
      check — starting a Windows build under a running Linux lane still
      clobbers the shared generated files.
- [b] `export_android_gstreamer_env` (`scripts/linux/lib/container-steps.sh`)
      only exists because the image ships the Android GStreamer SDK at
      `/opt/android/gstreamer` without exporting `GSTREAMER_ROOT_ANDROID`. It is
      already written to no-op when the variable is set, so it can be deleted
      outright once the image exports it — blocked on that. Same shape as the
      six workarounds that were deleted on 2026-09-05.

## Open — release and repository state

- [ ] **`main` is 246 commits behind `develop`**, last synced by PR #23. Decide
      what `main` is for. If it is the release branch, that gap is the finding;
      if nothing reads it, say so in a doc and stop carrying it. Nothing in
      `.github/workflows/` triggers on `main` alone any more, so today it costs
      nothing but confuses every reader.
- [ ] **`version:` is still `1.1.0+1`**, which is what the annotated tag
      `1.1.0+1` already names — 246 commits ago. `app-packaging.sh` stamps it
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
      returns `404 Branch not protected` for both. That also makes
      `web.yml`'s claim that its job name "is the
      required-status-check string on develop's branch protection" stale. Either
      set protection (owner action — deciding what to require is the whole
      point) or stop referencing it.
- [ ] **The Linux artifacts each carry the 59 MB detector model** since
      2026-09-17 (`data/resources/models/yolov10m.onnx`, in tar/deb/AppImage/
      flatpak). That is the "works out of the box" choice;
      `KATAGLYPHIS_BUNDLE_MODEL=0` on the lane drops it for a smaller artifact
      that then needs `KATAGLYPHIS_ONNX_MODEL` at runtime. Decide if the default
      should flip.
- [ ] Dependabot #43 is blocked for a real reason, recorded as CON5 on
      ANTfrastructure's backlog: it moves `permission_handler_android` to 14.x,
      which needs `compileSdk 37` while the image is read-only at android-36.
      (#40, mockito, is closed — nothing imported it, so the dev dependency was
      dropped rather than bumped on 2026-09-17.)

## Open — hygiene

- [ ] The Linux and Windows images resolve different dependency versions, so
      `pubspec.lock` flips back and forth: a Linux lane run writes intl 0.20.3
      and matcher 0.12.20, the next Windows run writes 0.20.2 and 0.12.19. Both
      are committed states at different times, so whoever runs last "wins" and
      the diff is pure noise. **Measured 2026-09-17: the images carry different
      SDKs** — `:latest-cross` is Flutter 3.47.3 / Dart 3.13.3, `winamd64` is
      Flutter 3.44.8 / Dart 3.12.2 — so this is an image-alignment job
      (rebuild `winamd64` at the newer Flutter, or pin the Linux side back),
      not a pubspec fix. (The 2026-09-17 Linux resolution is currently
      committed; the mockito-drop diff is the 96 lines of its transitive
      crates.)
- [ ] `flutter pub get` reports packages held back by dependency constraints.
      Re-counted 2026-09-15 in `:latest-cross` (`flutter pub get --dry-run`):
      **20**, not the 45 this row claimed when it was written. Does not block a
      build today; re-count before acting on it, the number moves with the image.

## Open — the web lane's rustup step

- [ ] `rustup toolchain install nightly --component rust-src --target
      wasm32-unknown-unknown` (`ci-container-run-web-linux.sh`) fails in the
      container as soon as a **newer** nightly exists than the one the image
      baked:

      ```
      info: syncing channel updates for nightly-x86_64-unknown-linux-gnu
      info: latest update on 2026-09-16 for version 1.100.0-nightly (215a8af4b)
      info: removing previous version of component cargo
      info: rolling back changes
      error: could not rename 'component' file from
        '/usr/local/rustup/toolchains/nightly-x86_64-unknown-linux-gnu/share/zsh/site-functions'
        to '/usr/local/rustup/tmp/…/bk': Invalid cross-device link (os error 18)
      ```

      Observed 2026-09-16 on the local lane. The step is documented as
      "idempotent, and a no-op once the image ships them" (AGENTS.md § 4) — that
      is true only while the image's nightly *is* the latest nightly. On any
      later day rustup tries to UPDATE it, and the update renames files out of a
      read-only overlay layer into `$RUSTUP_HOME/tmp`, which is EXDEV.
      The Dart gate runs before this step and passed, so the failure is confined
      to the wasm half.

      **Worked around 2026-09-16** by guarding the step on the components
      actually being absent, matching the `command -v
      flutter_rust_bridge_codegen` guard three lines below it. Verified in
      `:latest-cross`: both `rust-src` and `wasm32-unknown-unknown` report
      `(installed)`, so the guard skips the install and the lane no longer
      touches rustup at all.

      That is a workaround, not the fix. **The image is the right place:** it
      already ships both components, so it should also ensure nothing needs to
      update them — either by pinning nightly to a dated channel
      (`nightly-YYYY-MM-DD`) or by putting `RUSTUP_HOME` somewhere writable.
      Until then, a bare host with no nightly still takes the install path and
      is still exposed. Raise it against ANTfrastructure's image rather than
      adding more here.

## Open — verification gaps

- [ ] **G6 over the real `oxidant.dll` and the Pi producer bundle has not run
      since the hub pin moved to e72a9a37.** On Windows, OxidANT f018bec's
      `oxidant.dll` carries `C:\temp\onnx-src\onnxruntime\core\`, which the
      old census would have read as a `STALE` ORT. That was never observed: run
      35928030211 dies earlier, at `CMake Configure` and then `Rust DLL not
      found`. The only `oxidant.dll` on the dev box predates the marker. The
      Windows census was proved with synthetic PEs only. On Linux,
      `scripts/linux/cat-stream/package-producer-bundle.sh` proves
      `/bin/kataglyphis_cat_webrtc`, which carries the Linux string, with this
      repo's hub, and it has not been re-run. Check both after the next Windows
      build and the next Pi bundle.
- [ ] `scripts/windows/Start-Windows.ps1` now launches (2026-09-17) but the
      window cannot be seen from the agent's shell: it runs in **Session 0**,
      where ANGLE/DXGI surface creation fails (`SwapChain11 … 0x887A0022`,
      `EGL Error: Context Lost`) and there is no desktop. The engine, the Rust
      bridge and the frb version check all pass there — the residual is "no
      interactive desktop", not an app defect. Confirm on the console session.
- [ ] **The reusable Windows build container can carry a stale Dart AOT.**
      Symptom: the app dies at `RustLib.init` with `Bad state: oxidant's
      codegen version (2.12.0) should be the same as runtime version (2.13.0)`
      while `lib/src/rust/frb_generated.dart` reads 2.13.0 — `data/app.so` was
      a snapshot from before the bindings were regenerated, and Flutter's
      assemble reported it up to date even with a fresh `app.dill`. Remedy
      used: `-FreshContainer`. A durable fix would compare `data/app.so`
      against the kernel stamp in `Build-Windows.ps1` and force the AOT
      target when it is older.
- [ ] **The Windows container's sync-back plants unusable reparse points in
      the host tree.** Robocopy of the container's cargo cache into
      `third_party/OxidANT/target` writes Linux-style links as Windows reparse
      points with no readable target (found on
      `cxxbridge/rust/cxx.h`), and bsdtar then aborts the next inbound
      transfer with `Cannot stat: Invalid argument` — the build started with
      no scripts at all. Mitigated 2026-09-17 by excluding that path from
      `Build-Windows-Container.ps1`'s inbound stream (the container builds
      into its own `rust_target`); upstream's sync-back still writes them.
- [ ] **The Windows `-CodeQL` path is unscoped until upstream grows a config
      seam.** Exercised 2026-09-17 (the driver now forwards
      `-CodeQL`/`-CodeQLDownload`): the Rust extractor indexed every manifest
      under the source root — 187 of them, including corrosion's own test
      crates under `build/.../_deps` — and the C++ extractor followed the build
      into every vendored library. The run was aborted.
      `WindowsCodeQL.Common.psm1` builds its `database create`/`analyze` args
      with no way to pass `--codescanning-config`, so a scoped Windows run
      needs that parameter upstreamed (preferred) or a repo-local fork of
      `Invoke-BuildCodeQL`. The Linux/android scan is scoped by
      `.github/codeql/codeql-config.yml`. CI runs no CodeQL at all since
      2026-09-17 (owner directive) — this path is manual-only.
- [ ] **CodeQL's `paths-ignore` filters findings, not extraction.** The scoped
      config keeps third-party code out of the *analysis*, but a built
      language's extractor still reads those trees — GitHub's docs say limiting
      a built scan means limiting the build, and the 2026-09-17 proof run's
      rust database carries the whole cargo registry (21k files under
      `usr/local/cargo`, outside the source root). If scan cost matters, the
      levers are the Rust extractor's manual build mode or moving the Flutter
      build tree outside the source root; neither is small. Moot for CI, which
      no longer scans.
- [b] flatpak and AppImage on arm64 are only ever exercised in CI: locally
      `qemu-user` cannot carry `unshare(CLONE_NEWUSER)` through for bubblewrap,
      nor load the static-PIE `appimagetool` — AGENTS.md § 5. Blocked on a real
      arm64 machine; nothing to change here.

## Agentic loop

Adopted 2026-09-13: `scripts/agentic-loop/` (config, runner wrappers, prompt
overlays); executor model `opencode-go/deepseek-v4.1-flash`. Windows builds go
through `scripts/windows/Build-Windows-Container.ps1`. Run commands and rules:
AGENTS.md § 5.
