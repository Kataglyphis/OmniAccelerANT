#!/usr/bin/env bash
# test-publish-release.sh: publish-release.sh against a fake repo and a stand-in gh that records what it is asked.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
fails=0

# A repo root with the script at its own path, a CHANGELOG with three sections, one commit, and two packages.
mkdir -p "${work}/repo/scripts/linux" "${work}/bin" "${work}/pkgs" "${work}/empty"
cp "${here}/../publish-release.sh" "${work}/repo/scripts/linux/"
printf 'name: app\nversion: 2.1.0+3\n' > "${work}/repo/pubspec.yaml"
cat > "${work}/repo/CHANGELOG.md" <<'MD'
# Changelog

## Unreleased

Not yet.

## 2.1.0+3 — 2026-10-15

Visit statistics.

## 2.1.01 — not this one

## 2.0.0+2 — 2026-10-01

Older.
MD
git -C "${work}/repo" init -q
git -C "${work}/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m release
head="$(git -C "${work}/repo" rev-parse HEAD)"
printf 'deb' > "${work}/pkgs/omni-observant_2.1.0_arm64.deb"
printf 'msi' > "${work}/pkgs/omni-observant-2.1.0-windows-x64.msi"
# "gh release view" answers like GitHub: found when released-<tag> exists, else "release not found"; GH_DOWN fails it otherwise.
cat > "${work}/bin/gh" <<GH
#!/usr/bin/env bash
if [ "\$1 \$2" = "release view" ]; then
  [ -z "\${GH_DOWN:-}" ] || { echo "HTTP 401: Bad credentials" >&2; exit 1; }
  [ -e "${work}/released-\$3" ] && { echo "{\"tagName\":\"\$3\"}"; exit 0; }
  echo "release not found" >&2; exit 1
fi
printf '%s\n' "\$@" > "${work}/gh-args"
for a in "\$@"; do [ "\${prev:-}" = "--notes-file" ] && cp "\$a" "${work}/gh-notes"; prev="\$a"; done
GH
chmod +x "${work}/bin/gh"

run() { PATH="${work}/bin:${PATH}" bash "${work}/repo/scripts/linux/publish-release.sh" "$@" >"${work}/log" 2>&1; }
check() {
  if "${@:2}"; then printf 'ok    %s\n' "$1"; else printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); sed 's/^/      /' "${work}/log"; fi
}

check "--check passes a version with a section and no release" run --check
check "and names the tag" grep -q '^v2.1.0 is not released yet' "${work}/log"
check "--check creates nothing" test ! -e "${work}/gh-args"

run "${work}/pkgs"
check "the release is v<pubspec version>" bash -c "sed -n 3p '${work}/gh-args' | grep -qx v2.1.0"
check "and tags the commit it runs on" grep -qx -- "${head}" "${work}/gh-args"
check "every package goes up" grep -q 'omni-observant_2.1.0_arm64.deb' "${work}/gh-args"
check "the checksums go up too" grep -q '/SHA256SUMS$' "${work}/gh-args"
check "the checksums match the packages" bash -c "cd '${work}/pkgs' && sha256sum -c --quiet SHA256SUMS"
check "the checksums do not list themselves" bash -c "! grep -q 'SHA256SUMS' '${work}/pkgs/SHA256SUMS'"
check "the notes are the version's section" grep -qx 'Visit statistics.' "${work}/gh-notes"
check "and only that section" bash -c "! grep -qE 'Older|Not yet|not this one' '${work}/gh-notes'"

rm -f "${work}/gh-args"
touch "${work}/released-v2.1.0"
check "--check refuses a version that is released already" bash -c "! PATH='${work}/bin:${PATH}' bash '${work}/repo/scripts/linux/publish-release.sh' --check >'${work}/log' 2>&1"
check "and says to raise it" grep -q 'already released' "${work}/log"
check "a released version is not published again" bash -c "! PATH='${work}/bin:${PATH}' bash '${work}/repo/scripts/linux/publish-release.sh' '${work}/pkgs' >/dev/null 2>&1"
check "and calls no gh release create" test ! -e "${work}/gh-args"
rm -f "${work}/released-v2.1.0"

check "GitHub not answering is not 'not released'" bash -c "! GH_DOWN=1 PATH='${work}/bin:${PATH}' bash '${work}/repo/scripts/linux/publish-release.sh' --check >/dev/null 2>&1"

sed -i 's/^version: .*/version: 2.2.0+4/' "${work}/repo/pubspec.yaml"
check "a version the CHANGELOG has no section for fails --check" bash -c "! PATH='${work}/bin:${PATH}' bash '${work}/repo/scripts/linux/publish-release.sh' --check >/dev/null 2>&1"
check "and publishes nothing" bash -c "! PATH='${work}/bin:${PATH}' bash '${work}/repo/scripts/linux/publish-release.sh' '${work}/pkgs' >/dev/null 2>&1"

sed -i 's/^version: .*/version: 2.1.0+3/' "${work}/repo/pubspec.yaml"
check "a run without packages publishes nothing" bash -c "! PATH='${work}/bin:${PATH}' bash '${work}/repo/scripts/linux/publish-release.sh' '${work}/empty' >/dev/null 2>&1"
check "and calls no gh release create" test ! -e "${work}/gh-args"

if [ "${fails}" -gt 0 ]; then
  printf '%d of the release script checks failed\n' "${fails}"
  exit 1
fi
printf 'release script: all checks passed\n'
