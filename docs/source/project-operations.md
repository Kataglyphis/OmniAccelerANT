# Project Operations

Operational guide for contributors and maintainers.

## Daily Developer Flow

1. Update branch and submodules.
2. Run local checks (`flutter analyze`, selected tests, docs generation).
3. Verify at least one target runtime (web, linux, windows, or android).
4. Open pull request with clear scope and verification notes.

## Quality Gates

### Static checks

```bash
dart analyze
dart format --output=none --set-exit-if-changed $(git ls-files '*.dart')
```

Never `dart format .`: it walks `flutter/`, `third_party/` and `build/`, which
`dart format` cannot be told to skip — it ignores `analysis_options.yaml`. Both
lanes list tracked files instead, which is what the command above reproduces.

### Lint gates (shell, workflows, secrets)

```bash
bash scripts/linux/run-lint-gates.sh
```

The exact command the `lint` job of `dart_on_native_linux.yml` runs — shellcheck,
actionlint (plus the CI image-reference check) and the gitleaks secret scan, all
three bootstrapped pinned from ANTfrastructure, all three run even after one fails.
These used to exist only as `run:` blocks inside the workflow, so a failing merge
gate could not be reproduced locally at all. The gitleaks arm self-tests first: an
empty tree must scan clean and a planted token must be reported and must make the
gate exit non-zero, so "found nothing" cannot be confused with "never ran".

The shared-config drift check is one of that command's gates, not a separate
step: `bash scripts/linux/run-lint-gates.sh` runs it. The workflow's `pwsh`
`Sync-SharedConfig.ps1 -Check` step is the PowerShell twin of the same gate,
kept so both halves stay exercised and are required to agree.

### Tests

```bash
flutter test
flutter test integration_test/simple_test.dart
```

## Documentation Workflow

Generate docs:

```bash
bash scripts/linux/generate-docs.sh
```

Preview docs:

```bash
dhttpd --path doc/api --host 127.0.0.1 --port 8080
```

### There is no Sphinx site here

`docs/source/` is Markdown source for exactly one consumer: the `dart doc` site
that `scripts/linux/generate-docs.sh` builds, which stages each guide listed in
that script's `DARTDOC_BUILD_GUIDES` array. The `docs/Makefile`, `docs/make.bat`,
`docs/source/conf.py` and `docs/source/index.rst` that used to sit beside it were
scaffolding from `sphinx-quickstart` that no lane, workflow or script ever
invoked; they were deleted on 2026-09-15 and git history keeps them. Add a guide
by adding the file and one array row, not by reviving a second doc builder.

If a Sphinx site is ever wanted, take the shared theme rather than the
standalone `press` theme the deleted `conf.py` named: it lives in
[DocumANTation](https://github.com/Kataglyphis/DocumANTation), consumers vendor
it as `third_party/DocumANTation` and install it through a docs-scoped
requirements file (`-e ./third_party/DocumANTation/sphinx-kataglyphis-theme`),
and `conf.py` then reduces to
`from sphinx_kataglyphis import setup_theme; setup_theme(globals(), ...)`.

This repo carries no root `requirements.txt`: the only thing it ever fed was the
cmake-format gate, which now takes its pinned bootstrap set from
`third_party/ANTfrastructure/linux/scripts/cmake-format.requirements.txt`. A docs
requirements file would be docs-scoped for the same reason — an unpinned root
file next to a pinned shared one is exactly the drift that removal closed.

## CI/CD Notes

- Linux native, Windows native, Web, and Android pipelines are available via GitHub Actions.
- Keep generated artifacts deterministic to reduce CI diffs and flaky builds.
- Prefer script-driven commands from `scripts/` over ad-hoc commands for reproducibility.

## Release Hygiene

- Keep dependency upgrades and feature changes in separate pull requests.
- Regenerate bridge code when Rust API signatures change.
- Update docs in the same pull request for any user-facing behavior changes.

## Troubleshooting

### flutter_rust_bridge Version Mismatch

If you encounter this error at runtime:
```
oxidant's codegen version (2.11.1) should be the same as runtime version (2.12.0)
```

**Cause:** The generated Dart binding files (in `lib/src/rust/`) are out of sync with the `pubspec.yaml` dependency version.

**Fix:** Regenerate the Flutter Rust Bridge bindings:

```bash
flutter_rust_bridge_codegen generate
```

It is a cargo binary baked into the build image, not a pub dependency — on a
bare host install it first, at the version this repo pins rather than at latest:
`cargo install --locked --version 2.13.0 flutter_rust_bridge_codegen` (the
`flutter_rust_bridge` pin in `third_party/OxidANT/Cargo.toml`; the image exports
the same number as `FLUTTER_RUST_BRIDGE_VERSION`). Installing latest is how the
mismatch above happens in the first place.

Then rebuild the project:
```bash
# For Windows
.\scripts\windows\Build-Windows.ps1 -BuildRootDir build
```

**Prevention:** Always regenerate bindings after updating `flutter_rust_bridge` version in `pubspec.yaml` or modifying Rust API signatures.

## Contribution Checklist

- [ ] Scope is focused and documented.
- [ ] Build/test commands were run locally.
- [ ] Relevant docs were updated.
- [ ] No secrets, machine-specific paths, or temporary artifacts were committed.