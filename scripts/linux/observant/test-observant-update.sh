#!/usr/bin/env bash
# test-observant-update.sh: the camera updater against a local stand-in for GitHub's releases and tiny fake packages; root, in a container.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
fails=0
cleanup() {
  [ -n "${server:-}" ] && kill "${server}" 2>/dev/null
  dpkg -P omni-observant >/dev/null 2>&1 || true
  rm -rf "${work}" /var/lib/omni-observant-update-test
}
trap cleanup EXIT

# A package named omni-observant at <version> for <arch>, with nothing in it but a marker.
fake_deb() {
  local root="${work}/pkg-$1-$2"
  mkdir -p "${root}/DEBIAN" "${root}/usr/share/omni-observant-update-test"
  printf '%s\n' "$1" > "${root}/usr/share/omni-observant-update-test/version"
  printf 'Package: omni-observant\nVersion: %s\nArchitecture: %s\nMaintainer: test <t@t>\nDescription: fake\n' \
    "$1" "$2" > "${root}/DEBIAN/control"
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

installed() { dpkg-query -W -f='${Version}' omni-observant 2>/dev/null; }
update() { bash "${updater}" >"${work}/update.log" 2>&1; }
check() {
  if "${@:2}"; then printf 'ok    %s\n' "$1"; else printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); sed 's/^/      /' "${work}/update.log"; fi
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

if [ "${fails}" -gt 0 ]; then
  printf '%d of the updater checks failed\n' "${fails}"
  exit 1
fi
printf 'updater: all checks passed\n'
