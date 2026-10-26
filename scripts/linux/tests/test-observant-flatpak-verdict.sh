#!/usr/bin/env bash
# Stubbed Flatpak tools cover the commit and artifact verdict, not a real sandbox or runtime.
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${repo}/scripts/linux/lib/antfrastructure.sh"
_harness="$(antfrastructure_path linux/scripts/lib/test-harness.sh)" || exit 1
# shellcheck source=third_party/ANTfrastructure/linux/scripts/lib/test-harness.sh
source "${_harness}"
subject="${OBSERVANT_FLATPAK_SOURCE:-${repo}/scripts/linux/observant/package-observant.sh}"
hub_packaging="$(antfrastructure_path linux/scripts/lib/app-packaging.sh)" || exit 1
flatpak_fn="$(t_fn_src "${subject}" package_observant_flatpak)" || exit 1
commit_fn="$(t_fn_src "${hub_packaging}" app_packaging_assert_flatpak_committed)" || exit 1
artifact_fn="$(t_fn_src "${hub_packaging}" app_packaging_assert_artifact)" || exit 1
root="$(mktemp -d "${TMPDIR:-/tmp}/observant-flatpak-verdict.XXXXXX")" || exit 1
trap 'rm -rf -- "${root}"' EXIT
mkdir -p "${root}/bin" "${root}/bundle" "${root}/out"
printf 'payload\n' > "${root}/bundle/observant"
printf 'FLATPAK_RUNTIME_VERSION=26.08\n' > "${root}/versions.env"

cat > "${root}/bin/flatpak-builder" <<'STUB'
#!/usr/bin/env bash
printf 'builder\n' >> "${STUB_LOG}"
exit "${STUB_FB_RC:-0}"
STUB
cat > "${root}/bin/ostree" <<'STUB'
#!/usr/bin/env bash
if [ "${STUB_OSTREE_EMPTY:-0}" != 1 ]; then printf 'app/org.kataglyphis.omni-observant/x86_64/stable\n'; fi
STUB
cat > "${root}/bin/flatpak" <<'STUB'
#!/usr/bin/env bash
printf 'flatpak %s\n' "$1" >> "${STUB_LOG}"
if [ "$1" = build-bundle ]; then
  if [ "${STUB_EMPTY_BUNDLE:-0}" = 1 ]; then : > "$3"; else printf 'bundle\n' > "$3"; fi
fi
STUB
chmod +x "${root}/bin/flatpak-builder" "${root}/bin/ostree" "${root}/bin/flatpak"

probe() {
  local label="$1" rc=0
  shift
  mkdir -p "${root}/${label}/work" "${root}/${label}/out"
  : > "${root}/${label}/calls"
  env PATH="${root}/bin:${PATH}" CASE_ROOT="${root}/${label}" STUB_LOG="${root}/${label}/calls" \
    OBSERVANT_FN="${flatpak_fn}" COMMIT_FN="${commit_fn}" ARTIFACT_FN="${artifact_fn}" \
    VERSION_FILE="${root}/versions.env" REPO_ROOT="${repo}" "$@" bash -c '
      set -euo pipefail
      eval "$OBSERVANT_FN"
      eval "$COMMIT_FN"
      eval "$ARTIFACT_FN"
      antfrastructure_path() { printf "%s\n" "$VERSION_FILE"; }
      app_packaging_ensure_flatpak_runtime() { :; }
      work="$CASE_ROOT/work"
      bundle="${CASE_ROOT%/*}/bundle"
      script_dir="$REPO_ROOT/scripts/linux/observant"
      repo_root="$REPO_ROOT"
      out_dir="$CASE_ROOT/out"
      package=omni-observant
      version=1.2.3
      flatpak_file="$out_dir/${package}-${version}-$(uname -m).flatpak"
      package_observant_flatpak
    ' > "${root}/${label}/output" 2>&1 || rc=$?
  printf '%s\n' "$rc" > "${root}/${label}/rc"
}

t_case 'a green builder without an OSTree app ref cannot ship a Flatpak'
probe missing-ref STUB_OSTREE_EMPTY=1
t_assert_eq 1 "$(cat "${root}/missing-ref/rc")"
t_assert_contains "$(cat "${root}/missing-ref/output")" 'is not in'
t_assert_eq '' "$(grep -F 'flatpak build-bundle' "${root}/missing-ref/calls" || true)"

t_case 'a committed app survives a late nonzero builder status'
probe committed STUB_FB_RC=1
t_assert_eq 0 "$(cat "${root}/committed/rc")"
t_assert_contains "$(cat "${root}/committed/output")" 'flatpak-builder exited 1'
t_assert_ok test -s "${root}/committed/out/omni-observant-1.2.3-$(uname -m).flatpak"

t_case 'an empty bundled artifact cannot report success'
probe empty-artifact STUB_EMPTY_BUNDLE=1
t_assert_eq 1 "$(cat "${root}/empty-artifact/rc")"
t_assert_contains "$(cat "${root}/empty-artifact/output")" 'missing or empty'

t_summary
