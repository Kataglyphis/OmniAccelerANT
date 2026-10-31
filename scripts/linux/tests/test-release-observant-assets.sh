#!/usr/bin/env bash
# Reads names from the updater and workflows; it does not cover riscv64, the uploaded files themselves, or the Windows MSI updater.
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${repo}/scripts/linux/lib/antfrastructure.sh"
_harness="$(antfrastructure_path linux/scripts/lib/test-harness.sh)" || exit 1
# shellcheck source=third_party/ANTfrastructure/linux/scripts/lib/test-harness.sh
source "${_harness}"
updater="${RELEASE_ASSETS_UPDATER:-${repo}/scripts/linux/observant/package/omni-observant-update}"
release="${RELEASE_ASSETS_WORKFLOW:-${repo}/.github/workflows/release.yml}"
lane="${RELEASE_ASSETS_LANE:-${repo}/.github/workflows/web.yml}"

package="$(sed -n 's/^package=//p' "${updater}")"
downloads="$(grep -oE '[$][{]releases[}]/download/v[$][{]latest[}]/[^"]+' "${updater}" | sed 's|.*/||' | sort -u)" || :
templates="$(sed -n 's/^ *asset="\(.*\)"$/\1/p' "${updater}")"
# The architectures the ObservANT package job builds, from its matrix platforms.
arches="$(awk '/^  [A-Za-z0-9_-]+:$/ { if (hit) exit; block = "" } { block = block $0 "\n" } /package-observant[.]sh/ { hit = 1 } END { if (hit) printf "%s", block }' "${lane}" |
  sed -n 's|^ *platform: linux/\([a-z0-9]*\)$|\1|p')"
expects="$(sed -n 's/^ *--expect //p' "${release}")"

t_case 'the inputs parse to a package, two asset shapes and the built architectures'
t_assert_eq omni-observant "${package}"
t_assert_eq 2 "$(printf '%s\n' "${templates}" | grep -c .)"
t_assert_eq 'amd64 arm64' "$(printf '%s\n' "${arches}" | sort | xargs)"

t_case 'every release download is an asset shape or the SHA256SUMS the hub publish step writes'
while IFS= read -r name; do
  case "${name}" in
    '${asset}'|SHA256SUMS) t_assert_ok true ;;
    *) t_assert_eq 'an asset or SHA256SUMS' "${name}" ;;
  esac
done <<< "${downloads}"
t_assert_contains "${downloads}" '${asset}'

t_case 'release.yml expects every package the updater downloads'
pkg_ref='${package}' ver_ref='${latest}' arch_ref='${arch}' ver='{version}'
while IFS= read -r template; do
  while IFS= read -r arch; do
    name="${template//"${pkg_ref}"/${package}}"
    name="${name//"${ver_ref}"/${ver}}"
    name="${name//"${arch_ref}"/${arch}}"
    t_assert_contains $'\n'"${expects}"$'\n' $'\n'"${name}"$'\n' 'release.yml --expect lacks an updater asset'
  done <<< "${arches}"
done <<< "${templates}"

t_summary
