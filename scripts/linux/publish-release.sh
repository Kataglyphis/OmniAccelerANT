#!/usr/bin/env bash
# publish-release.sh <tag> <dir>: the packages in <dir> as GitHub release <tag>, with SHA256SUMS and the tag's CHANGELOG.md section as notes.
set -euo pipefail

tag="${1:?usage: publish-release.sh <tag> <dir>}"
dir="${2:?usage: publish-release.sh <tag> <dir>}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

version="$(sed -n 's/^version:[[:space:]]*\([0-9][0-9.]*\).*/\1/p' "${root}/pubspec.yaml" | head -1)"
if [ -z "${version}" ] || [ "${tag}" != "v${version}" ]; then
  printf 'tag %s is not v%s, the version pubspec.yaml carries\n' "${tag}" "${version:-?}" >&2
  exit 1
fi

# The section headed "## <version>", a "+build" or " — date" after it, up to the next "## ".
notes="$(awk -v v="${version}" '
  /^## / {
    if (found) exit
    rest = substr($0, length("## " v) + 1, 1)
    found = (index($0, "## " v) == 1 && (rest == "" || rest == "+" || rest == " "))
    next
  }
  found { print }
' "${root}/CHANGELOG.md")"
if [ -z "$(printf '%s' "${notes}" | tr -d '[:space:]')" ]; then
  printf 'CHANGELOG.md has no section for %s\n' "${version}" >&2
  exit 1
fi

rm -f "${dir}/SHA256SUMS"
shopt -s nullglob
packages=("${dir}"/*)
if [ "${#packages[@]}" -eq 0 ]; then
  printf 'no packages in %s\n' "${dir}" >&2
  exit 1
fi
# The cameras' updater checks a download against this file before it installs anything.
(cd "${dir}" && sha256sum -- * > SHA256SUMS)

notes_file="$(mktemp)"
trap 'rm -f "${notes_file}"' EXIT
printf '%s\n' "${notes}" > "${notes_file}"
gh release create "${tag}" --verify-tag --title "OmniAccelerANT ${version}" \
  --notes-file "${notes_file}" "${packages[@]}" "${dir}/SHA256SUMS"
