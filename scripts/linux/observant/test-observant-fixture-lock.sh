#!/usr/bin/env bash
# The real packager on a lock naming another model, checked in the finished tar, .deb and AppImage; not covered: the flatpak's model files (its build still runs), riscv64, or that model running.
set -euo pipefail

# shellcheck source=scripts/linux/observant/lib/script-paths.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/script-paths.sh"
# shellcheck source=scripts/linux/observant/lib/locked-model.sh
source "${script_dir}/lib/locked-model.sh"

web_root="${1:?usage: test-observant-fixture-lock.sh <web root> [packages dir]}"
packages="${2:-${repo_root}/out}"
shipped="$(locked_model_name "${repo_root}/third_party/OxidANT/resources/models/models.lock")"
shipped="${shipped%.onnx}"
fixture=fixture_detector
package=omni-observant

work="$(mktemp -d /tmp/observant-fixture.XXXXXX)"
trap 'rm -rf "${work}"' EXIT
mkdir -p "${work}/source" "${work}/out" "${work}/producer"
export KATAGLYPHIS_MODEL_CACHE="${work}/cache"

for suffix in onnx LICENSE NOTICE; do
  path="${work}/source/${fixture}.${suffix}"
  printf 'fixture %s\n' "${suffix}" > "${path}"
  printf '%s  %s  file://%s\n' "$(sha256sum "${path}" | cut -d' ' -f1)" "${fixture}.${suffix}" "${path}" >> "${work}/models.lock"
done

# The producer of the packages this job just built: a second cargo build would prove nothing more.
built="$(find "${packages}" -maxdepth 1 -name "${package}-*-linux-*.tar.gz" | head -n 1 || true)"
[ -n "${built}" ] || { printf 'no %s tarball in %s\n' "${package}" "${packages}" >&2; exit 1; }
tar -xzf "${built}" -C "${work}/producer" --strip-components=2 "${package}/bin/kataglyphis_observant"

bash "${script_dir}/package-observant.sh" --web-root "${web_root}" --producer "${work}/producer/kataglyphis_observant" \
  --models-lock "${work}/models.lock" --out "${work}/out"

failed=0
check() {
  local what="$1" listing="$2" prefix="$3" suffix
  for suffix in models/${fixture}.onnx share/doc/${package}/${fixture}.LICENSE share/doc/${package}/${fixture}.NOTICE; do
    if ! grep -qF -e "${prefix}${suffix}" <<<"${listing}"; then
      printf 'FAIL %s: no %s\n' "${what}" "${prefix}${suffix}" >&2
      failed=1
    fi
  done
  if grep -qF -e "${shipped}" <<<"${listing}"; then
    printf 'FAIL %s: carries %s\n' "${what}" "${shipped}" >&2
    failed=1
  fi
}

tarball="$(find "${work}/out" -maxdepth 1 -name "${package}-*-linux-*.tar.gz")"
check tar "$(tar -tzf "${tarball}")" "${package}/"
launcher="$(tar -xzOf "${tarball}" "${package}/observant")"
grep -qF -e "/models/${fixture}.onnx" <<<"${launcher}" || { printf 'FAIL tar: the launcher does not start %s\n' "${fixture}" >&2; failed=1; }
notice="$(tar -xzOf "${tarball}" "${package}/share/doc/${package}/NOTICE-model")"
grep -qF -e "models/${fixture}.onnx" <<<"${notice}" || { printf 'FAIL tar: NOTICE-model does not name %s\n' "${fixture}" >&2; failed=1; }
if ! tar -xzOf "${tarball}" "${package}/models/${fixture}.onnx" | cmp -s - "${work}/source/${fixture}.onnx"; then
  printf 'FAIL tar: the model is not the fixture lock'"'"'s bytes\n' >&2
  failed=1
fi

check deb "$(dpkg-deb -c "$(find "${work}/out" -maxdepth 1 -name "${package}_*.deb")")" "./opt/${package}/"

appimage="$(find "${work}/out" -maxdepth 1 -name "${package}-*.AppImage")"
if [ -n "${appimage}" ]; then
  (cd "${work}" && "${appimage}" --appimage-extract >/dev/null)
  check appimage "$(cd "${work}/squashfs-root" && find . -type f)" './'
fi

[ "${failed}" = 0 ] || exit 1
printf 'PASS  the finished packages carry %s and not %s\n' "${fixture}" "${shipped}"
