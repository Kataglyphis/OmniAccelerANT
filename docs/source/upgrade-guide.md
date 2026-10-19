# Upgrade Guide

## Flutter/Rust Bridge Regeneration

Regenerate the bindings whenever a Rust function signature, struct, enum or module exposed to
Dart changes.

```bash
# Match the codegen to the `flutter_rust_bridge` pin in
# third_party/OxidANT/Cargo.toml (`=2.13.0` today). A floating latest writes
# bindings the Rust runtime then refuses at load time.
cargo install --locked --version 2.13.0 flutter_rust_bridge_codegen
flutter_rust_bridge_codegen generate
```

## Dependency Upgrades

**Flutter, Rust and the bridge's codegen come from the build image**, not from this repo: their
versions are the hub's pins in `third_party/ANTfrastructure/linux/scripts/01-core/versions.env`
(`FLUTTER_VERSION`, the Rust toolchains, `FLUTTER_RUST_BRIDGE_VERSION`). Moving one means a new
image, then the hub pin here.

**Submodules and manifests go through Renovate**, report first:
`scripts/linux/renovate-local.sh` on Linux, `scripts\windows\Invoke-Renovate.ps1` on Windows
([AGENTS.md § 5](../../AGENTS.md#dependency-upgrades), *Dependency upgrades*).

Recommended order:

1. One ecosystem at a time: Dart/Flutter, then Rust, then platform tooling.
2. Static checks and tests after each step.
3. Regenerate the docs and check for broken links and pages.

When upgrading `flutter_rust_bridge` on the Flutter side, the image's
`FLUTTER_RUST_BRIDGE_VERSION` must move with it: the web lane installs the codegen only when the
image has none, so it would build with the old one. Also run this in the Rust project,
`third_party/OxidANT`, its own repository: commit there, then move the gitlink here (AGENTS.md
§ 3):

```bash
cargo upgrade --pinned --package flutter_rust_bridge
```

## Validation Checklist

- [ ] `flutter analyze` passes
- [ ] Relevant tests pass
- [ ] `bash scripts/linux/generate-docs.sh` succeeds
- [ ] Streaming examples still run on at least one target device
