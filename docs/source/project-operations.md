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
flutter analyze
dart format --set-exit-if-changed .
```

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
kataglyphis_rustprojecttemplate's codegen version (2.11.1) should be the same as runtime version (2.12.0)
```

**Cause:** The generated Dart binding files (in `lib/src/rust/`) are out of sync with the `pubspec.yaml` dependency version.

**Fix:** Regenerate the Flutter Rust Bridge bindings:

```bash
flutter pub run flutter_rust_bridge_codegen
```

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