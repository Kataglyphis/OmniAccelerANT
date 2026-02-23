# Upgrade Guide

Use this guide when upgrading dependencies or changing Rust/Dart bridge APIs.

## Flutter/Rust Bridge Regeneration

Regenerate bindings whenever Rust function signatures, structs, enums, or modules exposed to Dart change.

```bash
cargo install flutter_rust_bridge_codegen
flutter_rust_bridge_codegen generate
```

## Dependency Upgrades

Recommended order:

1. Upgrade one ecosystem at a time (Dart/Flutter, then Rust, then platform tooling).
2. Run static checks and tests after each upgrade step.
3. Regenerate docs and verify no broken links/pages.

## Validation Checklist

- [ ] `flutter analyze` passes
- [ ] Relevant tests pass
- [ ] `bash scripts/linux/generate-docs.sh` succeeds
- [ ] Streaming examples still run on at least one target device