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
