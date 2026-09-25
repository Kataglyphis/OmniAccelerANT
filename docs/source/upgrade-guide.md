# Upgrade Guide

Use this guide when upgrading dependencies or changing Rust/Dart bridge APIs.

## Flutter/Rust Bridge Regeneration

Regenerate bindings whenever Rust function signatures, structs, enums, or modules exposed to Dart change.

```bash
# Match the codegen to the `flutter_rust_bridge` pin in
# third_party/OxidANT/Cargo.toml (`=2.13.0` today). A floating latest writes
# bindings the Rust runtime then refuses at load time.
cargo install --locked --version 2.13.0 flutter_rust_bridge_codegen
flutter_rust_bridge_codegen generate
```

## Dependency Upgrades

Recommended order:

1. Upgrade one ecosystem at a time (Dart/Flutter, then Rust, then platform tooling).
2. Run static checks and tests after each upgrade step.
3. Regenerate docs and verify no broken links/pages.

When upgrading `flutter_rust_bridge` on the Flutter side, also run this in the Rust project — `third_party/OxidANT`, its own repository: commit there, then move the gitlink here (AGENTS.md § 3):

```bash
cargo upgrade --pinned --package flutter_rust_bridge
```

## Validation Checklist

- [ ] `flutter analyze` passes
- [ ] Relevant tests pass
- [ ] `bash scripts/linux/generate-docs.sh` succeeds
- [ ] Streaming examples still run on at least one target device