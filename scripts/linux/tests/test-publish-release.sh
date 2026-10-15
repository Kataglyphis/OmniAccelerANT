#!/usr/bin/env bash
# test-publish-release.sh: publish-release.sh against a fake repo and a stand-in gh that records what it is asked.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
fails=0

# A repo root with the script at its own path, a CHANGELOG with three sections, and two packages.
mkdir -p "${work}/repo/scripts/linux" "${work}/bin" "${work}/pkgs"
cp "${here}/../publish-release.sh" "${work}/repo/scripts/linux/"
printf 'name: app\nversion: 2.1.0+3\n' > "${work}/repo/pubspec.yaml"
cat > "${work}/repo/CHANGELOG.md" <<'EOF'
# Changelog

## Unreleased

Not yet.

## 2.1.0+3 — 2026-10-15

Visit statistics.

## 2.1.01 — not this one

## 2.0.0+2 — 2026-10-01

Older.
EOF
printf 'deb' > "${work}/pkgs/omni-observant_2.1.0_arm64.deb"
printf 'msi' > "${work}/pkgs/omni-observant-2.1.0-windows-x64.msi"
cat > "${work}/bin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "${work}/gh-args"
for a in "\$@"; do [ "\${prev:-}" = "--notes-file" ] && cp "\$a" "${work}/gh-notes"; prev="\$a"; done
EOF
chmod +x "${work}/bin/gh"

publish() { PATH="${work}/bin:${PATH}" bash "${work}/repo/scripts/linux/publish-release.sh" "$@" >/dev/null 2>&1; }
check() {
  if "${@:2}"; then printf 'ok    %s\n' "$1"; else printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); fi
}

publish v2.1.0 "${work}/pkgs"
check "the tag's release is created from that tag" grep -qx 'v2.1.0' "${work}/gh-args"
check "it may not create the tag itself" grep -qx -- '--verify-tag' "${work}/gh-args"
check "every package goes up" grep -q 'omni-observant_2.1.0_arm64.deb' "${work}/gh-args"
check "the checksums go up too" grep -q '/SHA256SUMS$' "${work}/gh-args"
check "the checksums match the packages" bash -c "cd '${work}/pkgs' && sha256sum -c --quiet SHA256SUMS"
check "the checksums do not list themselves" bash -c "! grep -q 'SHA256SUMS' '${work}/pkgs/SHA256SUMS'"
check "the notes are the version's section" grep -qx 'Visit statistics.' "${work}/gh-notes"
check "and only that section" bash -c "! grep -qE 'Older|Not yet|not this one' '${work}/gh-notes'"

rm -f "${work}/gh-args"
check "a tag that is not pubspec's version publishes nothing" bash -c "! PATH='${work}/bin:${PATH}' bash '${work}/repo/scripts/linux/publish-release.sh' v2.0.0 '${work}/pkgs' 2>/dev/null"
check "and calls no gh" test ! -e "${work}/gh-args"

sed -i 's/^version: .*/version: 2.2.0+4/' "${work}/repo/pubspec.yaml"
check "a version the CHANGELOG has no section for publishes nothing" bash -c "! PATH='${work}/bin:${PATH}' bash '${work}/repo/scripts/linux/publish-release.sh' v2.2.0 '${work}/pkgs' 2>/dev/null"

sed -i 's/^version: .*/version: 2.1.0+3/' "${work}/repo/pubspec.yaml"
mkdir "${work}/empty"
check "a run without packages publishes nothing" bash -c "! PATH='${work}/bin:${PATH}' bash '${work}/repo/scripts/linux/publish-release.sh' v2.1.0 '${work}/empty' 2>/dev/null"
check "and calls no gh" test ! -e "${work}/gh-args"

if [ "${fails}" -gt 0 ]; then
  printf '%d of the release script checks failed\n' "${fails}"
  exit 1
fi
printf 'release script: all checks passed\n'
