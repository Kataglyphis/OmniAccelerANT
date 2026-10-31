#!/usr/bin/env bash
# Refuse unsafe checkouts, then generate both sides through OxidANT's one bridge configuration.
set -euo pipefail
for name in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_PREFIX; do
  if [[ ${!name+x} ]]; then
    printf 'Refusing Git repository override: %s\n' "$name" >&2
    exit 1
  fi
done
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo"
python3 -I - <<'PY'
import pathlib
import stat

for name in ("third_party", "third_party/OxidANT", "lib", "lib/src", "lib/src/rust"):
    path = pathlib.Path(name)
    metadata = path.lstat()
    if path.is_symlink() or getattr(metadata, "st_file_attributes", 0) & 0x400 or not stat.S_ISDIR(metadata.st_mode):
        raise SystemExit(f"FRB input/output directory is linked or not a directory: {path}")
PY
gitlink=$(git ls-files --stage -- third_party/OxidANT)
if [[ ! "$gitlink" =~ ^160000[[:space:]]([[:xdigit:]]{40})[[:space:]]0[[:space:]]third_party/OxidANT$ ]]; then
  echo 'OxidANT must have exactly one resolved gitlink in the index' >&2; exit 1
fi
pinned=${BASH_REMATCH[1]}
checkout=$(git -C third_party/OxidANT rev-parse HEAD)
[[ "$checkout" == "$pinned" ]] || { echo 'OxidANT checkout differs from the recorded index gitlink' >&2; exit 1; }
source_flags=$(git -C third_party/OxidANT ls-files -v)
dart_flags=$(git ls-files -v -- lib/src/rust)
if grep -E '^[a-zS] ' <<< "$source_flags" >/dev/null || grep -E '^[a-zS] ' <<< "$dart_flags" >/dev/null; then
  echo 'Refusing hidden assume-unchanged or skip-worktree source or binding files' >&2; exit 1
fi
source_changes=$(git -C third_party/OxidANT status --porcelain --untracked-files=all --ignore-submodules=none)
[[ -z "$source_changes" ]] || { echo 'OxidANT source checkout has tracked or untracked changes' >&2; exit 1; }
source_ignored=$(git -C third_party/OxidANT ls-files --others --ignored --exclude-standard -- \
  src crates third_party .cargo Cargo.toml Cargo.lock build.rs rust-toolchain.toml \
  ':(exclude)target/**' ':(exclude)**/target/**' ':(exclude)**/*.log')
[[ -z "$source_ignored" ]] || { echo 'OxidANT source inputs contain ignored files' >&2; exit 1; }
dart_changes=$(git status --porcelain --untracked-files=all -- lib/src/rust)
rust_changes=$(git -C third_party/OxidANT status --porcelain --untracked-files=all -- src/frb_generated.rs)
dart_ignored=$(git ls-files --others --ignored --exclude-standard -- lib/src/rust)
rust_ignored=$(git -C third_party/OxidANT ls-files --others --ignored --exclude-standard -- src/frb_generated.rs)
[[ -z "$dart_changes$rust_changes$dart_ignored$rust_ignored" ]] || { echo 'Refusing to overwrite changed generated bindings' >&2; exit 1; }
# OxidANT owns the bridge input, flags, generator pin and loader check; this app supplies only its roots.
bash third_party/OxidANT/scripts/linux/frb-codegen.sh generate --hub third_party/ANTfrastructure \
  --rust-root third_party/OxidANT --dart-output lib/src/rust
