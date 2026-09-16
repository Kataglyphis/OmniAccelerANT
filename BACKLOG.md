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

- [ ] `detect_arch` (`scripts/linux/lib/cli-common.sh`) silently returns `x64`
      for anything it does not recognise, so a riscv64 host would build and
      package as amd64 rather than failing. Upstream's `arch_normalize` passes
      unknown values through instead. Three lane scripts call it.
- [ ] `rust_builder/windows/CMakeLists.txt` still resolves the Rust manifest
      against `CMAKE_CURRENT_SOURCE_DIR`; the Linux twin was changed to
      `REALPATH` because the ephemeral plugin symlink made the `..` chain
      overshoot. Windows is green today only because `Build-Windows.ps1` has a
      `Fix Plugin Symlinks (Junctions)` step. Aligning the two needs a full
      Windows container build to prove it — see AGENTS.md § 4.

## Open — Linux Rust webcam inference (landed 2026-09-16, not yet usable)

All four links are in the tree and the lane is green, but nothing here has
produced a frame and nothing this repo publishes can run the feature off the
build image. Ordered so each item is independently verifiable.

- [ ] **The packaged Linux artifacts do not carry their GStreamer closure, and
      this is true even with the features OFF.** `readelf -d` on
      `bundle/lib/libkataglyphis_native_inference_plugin.so` lists eight
      unconditional `DT_NEEDED` entries — `libgstreamer-1.0.so.0`,
      `libgstbase`, `libgstapp`, `libgstvideo`, `libgstwebrtc`, `libgstsdp`,
      `libgstanalytics` — and `bundle/lib/` contains none of them, while the
      `.deb` declares only `libc6`, `libstdc++6`, `libgtk-3-0`
      (`app-packaging.sh`). So tar and deb only start on a host that already
      has GStreamer 1.29. Invisible in the build image, whose ld.so cache has
      everything — which is why a green lane never caught it. The flatpak may
      be fine (`org.freedesktop.Platform` ships GStreamer); AppImage is
      unchecked. Precedent for the fix is in this repo:
      `scripts/linux/cat-stream/package-producer-bundle.sh` globs the closure
      and writes a launcher. Decide bundle-the-closure vs declare-the-dependency
      before writing code; they are different products.
- [ ] **A `readelf`-based closure gate would have caught the row above in one
      second, with no display and no container-in-container.** For the runner
      and every `bundle/lib/*.so`, read `DT_NEEDED` and fail unless each name is
      bundled or in an allowlist that is literally the `.deb`'s `Depends` set.
      Natural home: `scripts/linux/run-native-linux.sh`, after the Flutter build
      and before packaging. Deterministic and arch-independent, unlike anything
      that needs to launch the app.
- [ ] **`liboxidant.so` has no `RUNPATH`, so ort's `dlopen` cannot find the
      bundled ONNX Runtime even though the file is now there.** `readelf -d`
      shows the runner carrying `RUNPATH [/opt/gcc-16.2.0/lib64:$ORIGIN/lib]`
      and `liboxidant.so` carrying none — and glibc resolves a `dlopen` against
      the *calling* object's search path, not the executable's. 02886c3 fixed
      the linked dependency (`libonnxruntime.so.1` is a real `DT_NEEDED` and is
      bundled); the runtime-loaded half still needs either `ORT_DYLIB_PATH` set
      by a launcher — `package-producer-bundle.sh` already writes exactly such a
      launcher — or `RUNPATH` on the cargokit output.
- [ ] **Nothing sets `KATAGLYPHIS_ONNX_MODEL`, and a packaged build has no
      model.** `grep -rn KATAGLYPHIS_ONNX_MODEL scripts/ rust_builder/ lib/
      pubspec.yaml` returns nothing. OxidANT's fallback resolves to
      `<workspace>/resources/models/yolov10m.onnx` (fixed in 7b8ffb3 — it used
      to name a directory that never existed), which is the checkout, not a
      bundle. Local runs work only because the 61 MB model sits at
      `/workspace`. Either the launcher points at a bundled model or the UI
      fails with "no model configured"; both beat file-not-found.
- [ ] **No lane sets `KATAGLYPHIS_RUST_FEATURES`, so CI has never built the
      Linux feature path.** The only setter in the repo is
      `scripts/windows/Build-Windows.ps1:211-212`. Every Linux lane run to date,
      local and CI, built the crate featureless. Turning it on in
      `run-native-linux.sh` or the workflow is a small change — but land it
      AFTER the closure work above, or CI starts publishing a featured artifact
      that cannot start.
- [ ] **`scripts/linux/check-knt-abi.sh` is not wired into anything.**
      `grep -rn check-knt-abi scripts/ .github/` finds only the script and its
      docs. It is the one piece of real verification the feature has, and it
      runs only when a human remembers. Its `--bundle-lib` default is also
      hard-coded to `build/linux/x64/release/bundle/lib`, so it needs
      parameterising from the lane's arch and build mode first.
- [b] **No frame has travelled Rust → `knt_push_frame` → texture.** Blocked on
      hardware, not on code: frames end in a GTK texture and no lane has a
      `DISPLAY`. The dev box is Windows with a C920 and `usbipd` installed, so
      the route exists (§ 4) — attach the camera to WSL, run the bundle under
      Xvfb in the image, and grep the log for
      `[my_texture] first pushed frame`. Needs `xvfb` in the image, or an
      `apt-get install` as root inside the container.

## Open — smaller code leftovers

- [ ] **`MyTexture`'s `copy_pixels` and `set_color` still race.** 2026-09-16
      added a `pushed_mutex` covering the `knt_push_frame` path and fixed the
      32-bit overflow in both, but `set_color` writes `self->buffer` while
      `copy_pixels` reads it with no shared lock. Clicking a colour button
      during playback tears rather than crashes, because the buffer is never
      reallocated after `my_texture_new` — which is why this is a leftover and
      not the bus-watch-level bug it resembles. Windows solved the same shape
      with a `present_buffer_`; record whichever way it goes in a comment, so
      the asymmetry is not "fixed" by accident later.
- [ ] **Dead Windows arm in `stream_page.dart`.** The `if (_isWindows)` branch
      that sends `setPipeline` as a map is unreachable: `_useRustWebcam` is
      unconditionally true on Windows, so the MethodChannel path is never taken
      there. Harmless, and deleting it needs no Windows build — but it reads as
      a live platform difference.
- [ ] **`books/` and `games/` markdown are missing**, ratcheted in
      `test/settings_asset_paths_test.dart`'s `_knownMissing`. Every `/books/*`
      and `/games/*` route renders a failed load on the deployed web build.
      Equivalents exist under `dummy_assets/`, so this is a content decision,
      not a recovery problem. Shrink the ratchet set; never grow it.

## Open — duplication and drift

- [ ] Android SDK component versions are pinned in four places: the global
      `subprojects` override in `android/build.gradle.kts`, plus
      `buildToolsVersion`/`ndkVersion`/`cmake.version` in `android/app`,
      `packages/kataglyphis_native_inference/android` and
      `rust_builder/android`. The override makes most of them redundant. They
      must all match what the CI image ships (`/opt/android-sdk` is read-only),
      so one source of truth would remove a whole class of failure — this
      session spent five runs discovering them one module at a time.
- [ ] `Invoke-LinuxLane.ps1` repeats each workflow's argument list. The sets
      were verified identical, but nothing enforces that: a flag added to a
      workflow and not to the driver silently breaks local/CI parity, which is
      the entire point of the driver. **Sharpened 2026-09-16:** the flag *names*
      were identical and the parity was still broken — `-StrictChecks` defaulted
      to `'false'` while both workflows passed `true`, so the driver graded less
      than CI for every local run. A checker that diffs flag names would not
      have caught it; it has to compare the **values** the driver actually
      sends, which means invoking it with `-WhatIf`-style arg capture (the
      command line is already echoed at `:163`) and diffing against the
      workflow's `script:` block.
- [ ] `scripts/linux/lib/packaging-common.sh` keeps 7 alias functions so the
      existing call sites need no change (the 9 that had no caller left are
      gone). Call sites should move to the upstream `app_packaging_*` names
      and the remaining aliases go.
- [ ] Nothing stops two local lanes from running against the same checkout at
      once, although the generated files at its root are per-host
      (`android/local.properties`, the ephemeral plugin symlinks, `.dart_tool`).
      `Invoke-LinuxLane.ps1` and `Build-Windows.ps1` could refuse to start while
      another lane's container is up — the failure is otherwise attributed to
      the innocent lane, see AGENTS.md § 5.
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
      were switched does not guard `develop`. This repo already protected
      `develop`; the others may now have an unprotected default.
- [ ] **Three of the four build lanes have no concurrency group.** The web lane
      got one when it gained a `pull_request` trigger; native, android and
      windows did not. Consecutive pushes to one ref run in full, in parallel.
      Cancelling an in-progress Windows or Android run has a different cost
      profile from the web one, which is why it was left as its own decision.
- [ ] **Dependabot #40 (mockito 5.7.0 → 5.8.1) may be the wrong fix.** Check
      whether anything imports `mockito` — if nothing does, drop the dev
      dependency rather than bumping it. It will also need a rebase against the
      current `pubspec.lock`. (#43 is blocked for a real reason, recorded as
      CON5 on ANTfrastructure's backlog: it moves
      `permission_handler_android` to 14.x, which needs `compileSdk 37` while
      the image is read-only at android-36.)

## Open — hygiene

- [ ] Leftovers from before the image and packaging fixes are still on disk and
      git-ignored, but large and confusing: `flutter/` (2.5 GB, from when the
      lane installed the SDK into the workspace), `.ccache/`,
      `.flatpak-builder/`, `out/flatpak/`, `out/deb/`.
- [ ] The Linux and Windows images resolve different dependency versions, so
      `pubspec.lock` flips back and forth: a Linux lane run writes intl 0.20.3
      and matcher 0.12.20, the next Windows run writes 0.20.2 and 0.12.19. Both
      are committed states at different times, so whoever runs last "wins" and
      the diff is pure noise. One of the two images has a different Dart SDK
      constraint; find which and align them.
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

- [ ] **The Android Kotlin bus-error fix is unbuilt.**
      `KataglyphisNativeInferencePlugin.kt`'s `handleNoArgCommand` now reports
      `GStreamerNative.getLastError()` alongside the throwable, so a failed
      `play` says why instead of "play failed". Nothing has compiled it: the
      Android lane has a single matrix row, that row runs CodeQL, and CodeQL's
      Kotlin extractor stops Gradle before the Kotlin step (§ 4). It is a
      ten-line change shaped exactly like `handleSetPipeline` twenty lines
      above it, but "shaped like working code" is not a build. Cheapest fix is
      probably a Gradle unit-test task for that module alone, which would also
      give the plugin its first JVM test.
- [ ] `scripts/windows/Start-Windows.ps1` has never been launched: it needs a
      desktop session, not a container.
- [ ] The `-CodeQL` path of `Build-Windows.ps1` has never been exercised.
- [ ] Branch protection on `develop` may pin check names that no longer exist —
      the Linux matrix job names changed twice in one session.
- [b] flatpak and AppImage on arm64 are only ever exercised in CI: locally
      `qemu-user` cannot carry `unshare(CLONE_NEWUSER)` through for bubblewrap,
      nor load the static-PIE `appimagetool` — AGENTS.md § 5. Blocked on a real
      arm64 machine; nothing to change here.

## Agentic loop

Adopted 2026-09-13: `scripts/agentic-loop/` (config, runner wrappers, prompt
overlays); executor model `opencode-go/deepseek-v4.1-flash`. Windows builds go
through `scripts/windows/Build-Windows-Container.ps1`. Run commands and rules:
AGENTS.md § 5.
