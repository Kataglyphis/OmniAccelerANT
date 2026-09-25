# OmniAccelerANT planner overlay

Project truth: a Flutter/Dart app (`lib/`) targeting Windows, Linux, Android and
web, with a Rust core (`third_party/OxidANT`, bridged via flutter_rust_bridge)
and a C++ inference plugin (`packages/kataglyphis_native_inference`). Read
`AGENTS.md` first — it is the rulebook; § 2 links to the upstream documents
that own every shared procedure. Do not restate those procedures in a task.

- **The executor runs on Windows and builds in the family Windows image.**
  Task "Build" lines must name the loop's own driver,
  `scripts/windows/Build-Windows-Container.ps1` (preset aliases
  `clangcl-release`, `clangcl-debug`), or say explicitly that verification
  needs the Linux/Android/web lane. Never propose host-native cmake/ninja
  commands: the host's cmake is Strawberry Perl's 3.29.2 and fails at
  configure (AGENTS.md § 5).
- **Do not propose changes to generated or deliberately-pinned artefacts.**
  `lib/src/rust/` is committed generated code; the `dbName` string in
  `lib/src/db/sqlite3_loader_web.dart` is a deliberate browser-database name; the
  Android SDK pins live once, in `android/build.gradle.kts`'s `extra` block, and
  no module may repeat them as literals; and the two
  Windows pieces AGENTS.md § 2 (What ANTfrastructure owns) marks "deliberately not reused" must stay out.
- **Never plan a `dart format .`** — the recursive walk escapes the tracked
  file list and has rewritten the SDK before (AGENTS.md § 4).
- **Prefer tasks verifiable on Windows**, because that is where the executor
  runs. A task whose only verification is a foreign lane must say how the
  result will actually be observed.
- **One owner per fact.** If a task documents or touches a shared procedure,
  point at `AGENTS.md` or `third_party/ANTfrastructure/docs/INDEX.md` instead
  of copying the text into the task or a new doc.
