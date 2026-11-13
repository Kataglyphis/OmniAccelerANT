#!/usr/bin/env bash
# test-observant-update.sh: the camera updater, for a .deb and (--user) for a user install, against a local stand-in for GitHub's releases and tiny fake packages; root, in a container.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${here}/../lib/antfrastructure.sh"
_harness="$(antfrastructure_path linux/scripts/lib/test-harness.sh)" || exit 1
# shellcheck source=third_party/ANTfrastructure/linux/scripts/lib/test-harness.sh
source "${_harness}"
updater="${here}/package/omni-observant-update"
if [ "$(id -u)" -ne 0 ] || ! command -v dpkg >/dev/null || ! command -v python3 >/dev/null; then
  printf 'test-observant-update.sh needs root, dpkg and python3 (it installs fake packages)\n' >&2
  exit 2
fi
# Never on a real camera: the fake packages would replace the installed ObservANT.
if dpkg-query -W -f='${Version}' omni-observant >/dev/null 2>&1 && [ ! -e /var/lib/omni-observant-update-test ]; then
  printf 'omni-observant is installed here; run this in a throwaway container\n' >&2
  exit 2
fi
mkdir -p /var/lib/omni-observant-update-test

work="$(mktemp -d)"
arch="$(dpkg --print-architecture)"
# The user install's side runs as uid 1001, which cannot enter root's mktemp directories.
user_home="$(mktemp -d)"
user_tools="$(mktemp -d)"
chmod 755 "${user_tools}"
chown 1001:1001 "${user_home}"
cleanup() {
  [ -n "${server:-}" ] && kill "${server}" 2>/dev/null
  dpkg -P omni-observant >/dev/null 2>&1 || true
  rm -rf "${work}" "${user_home}" "${user_tools}" /var/lib/omni-observant-update-test
}
trap cleanup EXIT

# A package named omni-observant at <version> for <arch>, with nothing in it but a marker; [ok|broken] is what its /healthz says once installed.
fake_deb() {
  local root="${work}/pkg-$1-$2"
  mkdir -p "${root}/DEBIAN" "${root}/usr/share/omni-observant-update-test"
  printf '%s\n' "$1" > "${root}/usr/share/omni-observant-update-test/version"
  printf 'Package: omni-observant\nVersion: %s\nArchitecture: %s\nMaintainer: test <t@t>\nDescription: fake\n' \
    "$1" "$2" > "${root}/DEBIAN/control"
  if [ -n "${3:-}" ]; then
    printf '#!/bin/sh\nprintf %%s %s > %s\n' "$(health_body "$3")" "${work}/www/healthz" > "${root}/DEBIAN/postinst"
    chmod 755 "${root}/DEBIAN/postinst"
  fi
  dpkg-deb --root-owner-group --build "${root}" "${work}/omni-observant_$1_$2.deb" >/dev/null
}

# releases/<latest>: what /releases/latest points at; releases/download/v<version>/: the assets.
publish() {
  local version="$1" dir="${work}/www/releases/download/v$1"
  mkdir -p "${dir}"
  cp "${work}/omni-observant_${version}_${2:-${arch}}.deb" "${dir}/"
  (cd "${dir}" && sha256sum -- *.deb > SHA256SUMS)
  printf '%s' "${version}" > "${work}/www/latest"
}

# /healthz's body for a fake that comes up ok or broken.
health_body() { if [ "$1" = ok ]; then printf "'{\"ok\":true}'"; else printf "'{\"ok\":false}'"; fi; }

# A release tarball whose observant, asked for --install --user, installs itself and the version it carries; [ok|broken] as for fake_deb.
fake_tar() {
  local root="${work}/tar-$1/omni-observant"
  mkdir -p "${root}/share/omni-observant"
  printf '%s\n' "$1" > "${root}/share/omni-observant/version"
  cat > "${root}/observant" <<'STUB'
#!/bin/sh
[ "$*" = "--install --user" ] || exit 2
mkdir -p "$HOME/.local/opt/omni-observant" && cp -r "$(dirname "$0")/." "$HOME/.local/opt/omni-observant/"
STUB
  if [ -n "${2:-}" ]; then
    printf 'printf %%s %s > %s\n' "$(health_body "$2")" "${user_home}/healthz" >> "${root}/observant"
  fi
  chmod 755 "${root}/observant"
  tar -C "${work}/tar-$1" -czf "${work}/omni-observant-$1-linux-${arch}.tar.gz" omni-observant
}

publish_tar() {
  local dir="${work}/www/releases/download/v$1"
  mkdir -p "${dir}"
  cp "${work}/omni-observant-$1-linux-${arch}.tar.gz" "${dir}/"
  (cd "${dir}" && sha256sum -- *.tar.gz > SHA256SUMS)
  printf '%s' "$1" > "${work}/www/latest"
}

cat > "${work}/server.py" <<'EOF'
import http.server, os, sys
root = sys.argv[1]
class Releases(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=root, **k)
    def do_GET(self):
        if self.path == "/releases/latest":
            latest = os.path.join(root, "latest")
            self.send_response(302)
            plain = os.path.join(root, "latest-plain")
            if os.path.exists(latest):
                target = "/releases/tag/v" + open(latest).read()
            elif os.path.exists(plain):
                target = "/releases/tag/" + open(plain).read()
            else:
                target = "/releases"
            self.send_header("Location", target)
            self.end_headers()
        elif self.path.startswith("/releases/tag/") or self.path == "/releases":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"release page")
        else:
            super().do_GET()
    def log_message(self, *a):
        pass
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[2])), Releases).serve_forever()
EOF
mkdir -p "${work}/www"
port=$((20000 + RANDOM % 20000))
python3 "${work}/server.py" "${work}/www" "${port}" &
server=$!
for _ in $(seq 50); do curl -fs -o /dev/null "http://127.0.0.1:${port}/releases" && break; sleep 0.1; done
export OMNI_OBSERVANT_RELEASES="http://127.0.0.1:${port}/releases"
# The fakes' /healthz is a file the server hands out; seconds, not the board's minute and a half.
export OMNI_OBSERVANT_HEALTHZ="http://127.0.0.1:${port}/healthz" OMNI_OBSERVANT_HEALTH_WAIT=2 OMNI_OBSERVANT_HEALTH_POLL=0.2

installed() { dpkg-query -W -f='${Version}' omni-observant 2>/dev/null; }
update() { bash "${updater}" >"${work}/update.log" 2>&1; }
# check <name> <command...>: one assertion, run in this shell; a failed one shows the updater's log.
check() {
  local rc=0
  t_case "$1"
  "${@:2}" || rc=$?
  t_assert_eq 0 "${rc}" "exit code"
  if [ "${rc}" -ne 0 ]; then sed 's/^/      /' "${work}/update.log"; fi
  return 0
}

check "with nothing installed, it does nothing" bash -c "OMNI_OBSERVANT_RELEASES=http://127.0.0.1:1 bash '${updater}' >'${work}/update.log' 2>&1"

fake_deb 1.0.0 "${arch}"
dpkg -i "${work}/omni-observant_1.0.0_${arch}.deb" >/dev/null
check "with no release out, it does nothing" update
check "and says so" grep -q 'no ObservANT release' "${work}/update.log"
printf '1.0.0+1' > "${work}/www/latest-plain"
check "a latest release from before the v tags does nothing" update
check "and installs nothing" test "$(installed)" = 1.0.0
rm "${work}/www/latest-plain"
fake_deb 1.1.0 "${arch}"
publish 1.1.0
check "a newer release installs" update
check "and is the installed version now" test "$(installed)" = 1.1.0
check "and says what it did" grep -q 'installing omni-observant 1.1.0 over 1.0.0' "${work}/update.log"

check "the same release again changes nothing" update
check "and says it is up to date" grep -q 'is up to date' "${work}/update.log"

fake_deb 1.0.5 "${arch}"
publish 1.0.5
check "an older release is no downgrade" update
check "the version stays" test "$(installed)" = 1.1.0

fake_deb 1.2.0 "${arch}"
publish 1.2.0
printf '0000000000000000000000000000000000000000000000000000000000000000  omni-observant_1.2.0_%s.deb\n' "${arch}" \
  > "${work}/www/releases/download/v1.2.0/SHA256SUMS"
check "a package that fails its checksum is not installed" bash -c "! bash '${updater}' >'${work}/update.log' 2>&1"
check "the version stays after a bad checksum" test "$(installed)" = 1.1.0

other=riscv64
[ "${arch}" = riscv64 ] && other=arm64
fake_deb 1.3.0 "${other}"
publish 1.3.0 "${other}"
check "a release without this architecture's package is no error" update
check "and leaves the version alone" test "$(installed)" = 1.1.0
check "and says why" grep -q "has no omni-observant_1.3.0_${arch}.deb" "${work}/update.log"

printf '=== the health check after an install ===\n'
fake_deb 1.4.0 "${arch}" ok
publish 1.4.0
check "a board that did not answer before is not judged" update
check "and keeps the new version" test "$(installed)" = 1.4.0
check "and says it was not judged" grep -q 'did not answer ok at .* before the update' "${work}/update.log"
fake_deb 1.5.0 "${arch}" broken
publish 1.5.0
check "a release that does not come up ok fails the update" bash -c "! bash '${updater}' >'${work}/update.log' 2>&1"
check "and the version before is put back" test "$(installed)" = 1.4.0
check "and says so" grep -q 'putting 1.4.0 back and skipping 1.5.0' "${work}/update.log"
check "and remembers the version" test "$(cat /var/lib/omni-observant-update/skipped-version)" = 1.5.0
check "the next night skips that version" update
check "and says why" grep -q 'skipping 1.5.0: it failed its health check' "${work}/update.log"
check "and stays on the version that works" test "$(installed)" = 1.4.0
fake_deb 1.6.0 "${arch}" ok
publish 1.6.0
check "the release after it installs and stays" update
check "as the installed version" test "$(installed)" = 1.6.0
check "and is judged ok" grep -q 'omni-observant 1.6.0 answers ok' "${work}/update.log"
rm -f "${work}/www/healthz" /var/lib/omni-observant-update/skipped-version

printf '=== --user, a user install ===\n'
user_version="${user_home}/.local/opt/omni-observant/share/omni-observant/version"
user_installed() { cat "${user_version}" 2>/dev/null; }
user_update() {
  setpriv --reuid=1001 --regid=1001 --clear-groups env -i HOME="${user_home}" PATH="${1:-/usr/bin:/bin}" \
    OMNI_OBSERVANT_RELEASES="${OMNI_OBSERVANT_RELEASES}" OMNI_OBSERVANT_HEALTHZ="${OMNI_OBSERVANT_HEALTHZ}" \
    OMNI_OBSERVANT_HEALTH_WAIT=2 OMNI_OBSERVANT_HEALTH_POLL=0.2 bash "${updater}" --user >"${work}/update.log" 2>&1
}
user_update_fails() { if ! user_update "$@"; then return 0; fi; return 1; }
check "with no user install, it does nothing" user_update
check "and says so" grep -q 'not installed as a user install' "${work}/update.log"
mkdir -p "$(dirname "${user_version}")" && printf '2.0.0\n' > "${user_version}" && chown -R 1001:1001 "${user_home}"
fake_tar 2.1.0
publish_tar 2.1.0
check "a newer release's tarball installs for the user" user_update
check "and is the user's version now" test "$(user_installed)" = 2.1.0
check "and it worked on disk, leaving no download behind" test ! -e "${user_home}/.cache/omni-observant/update"
check "the same release again changes nothing" user_update
check "and says it is up to date" grep -q 'is up to date' "${work}/update.log"
fake_tar 2.2.0
publish_tar 2.2.0
printf '0000000000000000000000000000000000000000000000000000000000000000  omni-observant-2.2.0-linux-%s.tar.gz\n' "${arch}" \
  > "${work}/www/releases/download/v2.2.0/SHA256SUMS"
check "a tarball that fails its checksum is not installed" user_update_fails
check "the user's version stays after a bad checksum" test "$(user_installed)" = 2.1.0
# A distro without dpkg: the same tools, minus dpkg, so versions compare with sort -V.
for tool in /usr/bin/* /bin/*; do
  case "$(basename "${tool}")" in dpkg*) continue ;; esac
  [ -f "${tool}" ] && ln -sfn "${tool}" "${user_tools}/$(basename "${tool}")"
done
printf '2.9.0\n' > "${user_version}"
fake_tar 2.10.0
publish_tar 2.10.0
check "without dpkg, 2.10.0 is still newer than 2.9.0" user_update "${user_tools}"
check "and installs" test "$(user_installed)" = 2.10.0

# uid 1001 cannot enter root's work directory, so its fakes write /healthz in its home and the server follows a link.
printf '{"ok":true}' > "${user_home}/healthz" && chown 1001:1001 "${user_home}/healthz"
ln -sfn "${user_home}/healthz" "${work}/www/healthz"
fake_tar 2.11.0 broken
publish_tar 2.11.0
check "a user install that does not come up ok fails the update" user_update_fails
check "and the user's version before is put back" test "$(user_installed)" = 2.10.0
check "and the version is remembered for the user" test "$(cat "${user_home}/.local/state/omni-observant/skipped-version")" = 2.11.0
check "the next night skips it for the user too" user_update
check "and the user stays on the version that works" test "$(user_installed)" = 2.10.0

t_summary
