#!/usr/bin/env bash
# publish-release.sh --check | <dir>: release v<pubspec version> at HEAD with <dir>'s packages, a SHA256SUMS and the version's CHANGELOG section.
set -euo pipefail

mode="${1:?usage: publish-release.sh --check | publish-release.sh <dir>}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

version="$(sed -n 's/^version:[[:space:]]*\([0-9][0-9.]*\).*/\1/p' "${root}/pubspec.yaml" | head -1)"
if [ -z "${version}" ]; then
  printf 'pubspec.yaml has no version\n' >&2
  exit 1
fi
tag="v${version}"

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

# Every merge into main is a release, so a version may be released once; any other gh error is not "not released".
if view="$(gh release view "${tag}" --json tagName 2>&1)"; then
  printf '%s is already released: raise version: in pubspec.yaml and give it a CHANGELOG section\n' "${tag}" >&2
  exit 1
elif [[ "${view}" != *"not found"* ]]; then
  printf 'could not ask GitHub about %s: %s\n' "${tag}" "${view}" >&2
  exit 1
fi
if [ "${mode}" = --check ]; then
  printf '%s is not released yet and has its CHANGELOG section\n' "${tag}"
  exit 0
fi

dir="${mode}"
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
gh release create "${tag}" --target "$(git -C "${root}" rev-parse HEAD)" --title "OmniAccelerANT ${version}" \
  --notes-file "${notes_file}" "${packages[@]}" "${dir}/SHA256SUMS"
