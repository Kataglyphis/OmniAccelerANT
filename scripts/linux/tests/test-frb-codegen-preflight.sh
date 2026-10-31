#!/usr/bin/env bash
# Run the actual generator wrapper against isolated controlled outputs.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin" "$work/repo/scripts/linux" "$work/repo/third_party/OxidANT/src" "$work/repo/lib/src/rust"
cp "$repo/scripts/linux/generate-frb-bindings.sh" "$work/repo/scripts/linux/"
cp "$repo/scripts/linux/verify-frb-bindings.py" "$work/repo/scripts/linux/"
cat > "$work/repo/third_party/OxidANT/Cargo.toml" <<'TOML'
[workspace.dependencies]
flutter_rust_bridge = "=2.13.0"
[lib]
name = "oxidant"
TOML
cat > "$work/bin/git" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  ls-files)
    if [[ "$2" == --stage ]]; then
      printf '160000 %s 0\tthird_party/OxidANT\n' "${FAKE_INDEX:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}"
    elif [[ "$2" == -v ]]; then
      [[ -z ${FAKE_DART_FLAG:-} ]] || printf '%s lib/src/rust/frb_generated.dart\n' "$FAKE_DART_FLAG"
    else
      [[ ${FAKE_DART_IGNORED:-0} != 1 ]] || printf 'lib/src/rust/ignored.dart\n'
    fi ;;
  status)
    [[ ${FAKE_DART_DIRTY:-0} != 1 ]] || printf ' M lib/src/rust/frb_generated.dart\n' ;;
  -C)
    shift 2
    case "$1" in
      rev-parse) printf '%s\n' "${FAKE_CHECKOUT:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}" ;;
      status)
        if [[ " $* " == *' src/frb_generated.rs '* ]]; then
          [[ ${FAKE_RUST_DIRTY:-0} != 1 ]] || printf ' M src/frb_generated.rs\n'
        else
          [[ ${FAKE_SOURCE_DIRTY:-0} != 1 ]] || printf ' M src/api/onnx.rs\n'
        fi ;;
      ls-files)
        if [[ "$2" == -v ]]; then
          [[ -z ${FAKE_SOURCE_FLAG:-} ]] || printf '%s src/api/onnx.rs\n' "$FAKE_SOURCE_FLAG"
        elif [[ " $* " == *' crates '* ]]; then
          [[ ${FAKE_SOURCE_IGNORED:-0} != 1 ]] || printf 'crates/core/src/ignored.rs\n'
        else
          [[ ${FAKE_RUST_IGNORED:-0} != 1 ]] || printf 'src/frb_generated.rs\n'
        fi ;;
      *) exit 2 ;;
    esac ;;
  *) exit 2 ;;
esac
FAKE
cat > "$work/bin/cargo" <<'FAKE'
#!/usr/bin/env bash
[[ "$1" == metadata ]]
[[ ${FAKE_METADATA_FAIL:-0} != 1 ]]
FAKE
cat > "$work/bin/flutter_rust_bridge_codegen" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == --version ]]; then
  printf 'flutter_rust_bridge_codegen %s\n' "${FAKE_BINARY_VERSION:-2.13.0}"
  exit 0
fi
[[ "$1" == generate ]]
[[ " $* " == *' --no-add-mod-to-lib '* && " $* " == *' --no-auto-upgrade-dependency '* ]]
touch "$GENERATOR_SENTINEL"
[[ ${FAKE_GENERATOR_FAIL:-0} != 1 ]]
cat > lib/src/rust/frb_generated.dart <<DART
String get codegenVersion => '${FAKE_DART_VERSION:-2.13.0}';
int get rustContentHash => ${FAKE_DART_HASH:-42};
stem: '${FAKE_STEM:-oxidant}',
DART
cat > third_party/OxidANT/src/frb_generated.rs <<RUST
pub(crate) const FLUTTER_RUST_BRIDGE_CODEGEN_VERSION: &str = "${FAKE_RUST_VERSION:-2.13.0}";
pub(crate) const FLUTTER_RUST_BRIDGE_CODEGEN_CONTENT_HASH: i32 = ${FAKE_RUST_HASH:-42};
RUST
FAKE
chmod +x "$work/bin/git" "$work/bin/cargo" "$work/bin/flutter_rust_bridge_codegen"
export PATH="$work/bin:$PATH" GENERATOR_SENTINEL="$work/reached"
wrapper="$work/repo/scripts/linux/generate-frb-bindings.sh"
for mutation in FAKE_INDEX=invalid FAKE_CHECKOUT=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb FAKE_SOURCE_DIRTY=1 FAKE_SOURCE_IGNORED=1 FAKE_SOURCE_FLAG=h FAKE_SOURCE_FLAG=S FAKE_DART_FLAG=h FAKE_DART_FLAG=S FAKE_DART_DIRTY=1 FAKE_RUST_DIRTY=1 FAKE_DART_IGNORED=1 FAKE_RUST_IGNORED=1; do
  if env "$mutation" bash "$wrapper" >/dev/null 2>&1; then
    echo "Unsafe checkout or changed bindings accepted: $mutation" >&2; exit 1
  fi
  [[ ! -e "$GENERATOR_SENTINEL" ]] || { echo "Generator ran after unsafe preflight: $mutation" >&2; exit 1; }
done
if FAKE_METADATA_FAIL=1 bash "$wrapper" >/dev/null 2>&1; then
  echo 'Failed Cargo metadata was accepted' >&2; exit 1
fi
[[ ! -e "$GENERATOR_SENTINEL" ]] || { echo 'Generator ran after metadata failure' >&2; exit 1; }
if FAKE_BINARY_VERSION=2.12.0 bash "$wrapper" >/dev/null 2>&1; then
  echo 'Wrong generator binary version was accepted' >&2; exit 1
fi
[[ ! -e "$GENERATOR_SENTINEL" ]] || { echo 'Generator ran with wrong version' >&2; exit 1; }
if FAKE_GENERATOR_FAIL=1 bash "$wrapper" >/dev/null 2>&1; then
  echo 'Failed generator was accepted' >&2; exit 1
fi
[[ -e "$GENERATOR_SENTINEL" ]] || { echo 'Generator was not reached after valid metadata' >&2; exit 1; }
for mutation in FAKE_STEM=UNKNOWN FAKE_DART_VERSION=2.12.0 FAKE_RUST_VERSION=2.12.0 FAKE_RUST_HASH=43; do
  if env "$mutation" bash "$wrapper" >/dev/null 2>&1; then
    echo "Bad generated binding accepted: $mutation" >&2; exit 1
  fi
done
bash "$wrapper"
echo 'FRB generation preflight and binding checks passed'
