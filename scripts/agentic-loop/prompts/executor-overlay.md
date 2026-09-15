# OmniAccelerANT executor overlay

Build and test through the family Windows container. There is no working
host-native CMake here: the host's cmake is Strawberry Perl's 3.29.2 out of
`C:\Strawberry\c\bin` and fails `cmake_minimum_required` at configure (AGENTS.md
§ 4). Run everything else on the host as usual.

- **Build:**
  `pwsh -ExecutionPolicy Bypass -File scripts\windows\Build-Windows-Container.ps1 -Configurations clangcl-release`
  This drives `scripts/windows/Build-Windows.ps1` inside the Stevedore Windows
  container, reusing one container so the Cargo/sccache/pub caches survive
  between builds. It always skips docs and MSIX packaging, and runs the
  Dart+CMake format gate. Add `-SkipTests` when you will run the tests
  separately.
- **Test:**
  `pwsh -ExecutionPolicy Bypass -File scripts\windows\Build-Windows-Container.ps1 -TestsOnly`
  runs `flutter pub get`, `flutter analyze` and `flutter test` in the container.
- **Run container builds in the foreground and keep the session alive.** A
  headless session ends when you stop responding, and anything backgrounded is
  orphaned (see the shared prompt). Use the tool's 10-minute maximum per call
  and keep polling with bounded waits until the build finishes; never end a
  turn "waiting for a notification".
- **A container build reconfigures from scratch** (the build script resets its
  CMake directory) — expect minutes, not seconds. Do not kill a build that is
  still producing output.
- **Format only the files you touched.** Never `dart format .` (AGENTS.md
  § 3); the build's own format gate checks the tracked file list.
- **Do not stage build output.** `build/`, `logs/`, `.dart_tool/`, `.venv/`,
  `doc/api/` are gitignored. If `git status` shows them, leave them alone.
- **Deliberate traps — do not "fix" them:** committed generated code under
  `lib/src/rust/`; the `dbName` string in `lib/src/db/sqlite3_loader_web.dart`;
  the four agreeing Android SDK pins; and the pieces AGENTS.md § 2 (What ANTfrastructure owns) marks as
  deliberately not reused.
- **Read `AGENTS.md` before editing build scripts** — § 3 lists the traps that
  each cost at least one real run.
