# Backlog

Follows the protocol ContainerHub's agentic loop (`shared/agentic-loop/`)
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
- [ ] The Linux CodeQL driver swallows failures with `|| true`
      (`scripts/linux/codeql/codeql-common.sh`), while the Windows twin throws.
      A CodeQL run that produces no database currently reports success. This is
      a rewrite, not a move — the two sides disagree about what a failure is.
- [ ] `rust_builder/windows/CMakeLists.txt` still resolves the Rust manifest
      against `CMAKE_CURRENT_SOURCE_DIR`; the Linux twin was changed to
      `REALPATH` because the ephemeral plugin symlink made the `..` chain
      overshoot. Windows is green today only because `Build-Windows.ps1` has a
      `Fix Plugin Symlinks (Junctions)` step. Aligning the two needs a full
      Windows container build to prove it — see AGENTS.md § 3.

## Open — duplication and drift

- [ ] Android SDK component versions are pinned in four places: the global
      `subprojects` override in `android/build.gradle.kts`, plus
      `buildToolsVersion`/`ndkVersion`/`cmake.version` in `android/app`,
      `ExternalLib/Kataglyphis_NativeInferencePlugin/android` and
      `rust_builder/android`. The override makes most of them redundant. They
      must all match what the CI image ships (`/opt/android-sdk` is read-only),
      so one source of truth would remove a whole class of failure — this
      session spent five runs discovering them one module at a time.
- [ ] `Invoke-LinuxLane.ps1` repeats each workflow's argument list. The sets
      were verified identical, but nothing enforces that: a flag added to a
      workflow and not to the driver silently breaks local/CI parity, which is
      the entire point of the driver.
- [ ] `scripts/linux/lib/packaging-common.sh` keeps 15 alias functions so the
      existing call sites need no change. Call sites should move to the
      upstream `app_packaging_*` names and the aliases go.
- [ ] Nothing stops two local lanes from running against the same checkout at
      once, although the generated files at its root are per-host
      (`android/local.properties`, the ephemeral plugin symlinks, `.dart_tool`).
      `Invoke-LinuxLane.ps1` and `Build-Windows.ps1` could refuse to start while
      another lane's container is up — the failure is otherwise attributed to
      the innocent lane, see AGENTS.md § 4.
- [ ] `scripts/linux/lib/check-linux.sh` is a human entry point with its own
      `usage` block but lives in `lib/`, next to sourced libraries. Same for the
      naming of `run-native-linux.sh` / `run-android.sh`, which read as
      host-side scripts but are what the CI lane actually invokes.
- [b] `export_android_gstreamer_env` (`scripts/linux/lib/container-steps.sh`)
      only exists because the image ships the Android GStreamer SDK at
      `/opt/android/gstreamer` without exporting `GSTREAMER_ROOT_ANDROID`. It is
      already written to no-op when the variable is set, so it can be deleted
      outright once the image exports it — blocked on that. Same shape as the
      six workarounds that were deleted on 2026-09-05.

## Open — hygiene

- [ ] Generated files are tracked and every containerized build dirties them
      with whatever mount path was used: `ios/Flutter/Generated.xcconfig`,
      `ios/Flutter/flutter_export_environment.sh`, the macOS equivalents. They
      declare themselves "do not check into version control".
- [ ] Leftovers from before the image and packaging fixes are still on disk and
      git-ignored, but large and confusing: `flutter/` (2.5 GB, from when the
      lane installed the SDK into the workspace), `.ccache/`,
      `.flatpak-builder/`, `out/flatpak/`, `out/deb/`.
- [ ] `flutter pub get` reports 45 packages held back by dependency
      constraints, and Flutter warns that Gradle 8.14 / AGP 8.11.1 support ends
      soon (9.1.0 / 9.0.1 required). Neither blocks a build today.

## Open — verification gaps

- [ ] `scripts/windows/Start-Windows.ps1` has never been launched: it needs a
      desktop session, not a container.
- [ ] The `-CodeQL` path of `Build-Windows.ps1` has never been exercised.
- [ ] Branch protection on `develop` may pin check names that no longer exist —
      the Linux matrix job names changed twice in one session.
- [b] flatpak and AppImage on arm64 are only ever exercised in CI: locally
      `qemu-user` cannot carry `unshare(CLONE_NEWUSER)` through for bubblewrap,
      nor load the static-PIE `appimagetool` — AGENTS.md § 4. Blocked on a real
      arm64 machine; nothing to change here.

## Not adopted yet

The agentic loop itself — config, runner wrappers, `scripts/AgenticLoop/` — is
not set up here. Templates live in ContainerHub's
`shared/agentic-loop/templates/`.
