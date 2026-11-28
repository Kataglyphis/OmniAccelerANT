#!/usr/bin/env bash
# The web lane on stubs keeps setup_compiler_cache's sccache drain on exit and stops its smoke server; no real build runs.
set -uo pipefail

# shellcheck source=scripts/linux/tests/harness-bootstrap.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness-bootstrap.sh"
work="$(mktemp -d)"
trap '[ ! -s "${work}/server.pid" ] || kill "$(cat "${work}/server.pid")" 2>/dev/null; rm -rf "${work}"' EXIT

sandbox="${work}/repo"
mkdir -p "${sandbox}/scripts/linux/ci" "${sandbox}/scripts/linux/lib" "${sandbox}/scripts/linux/tests" "${work}/bin"
cp "${KATAGLYPHIS_REPO_ROOT}/scripts/linux/ci/ci-container-run-web-linux.sh" "${sandbox}/scripts/linux/ci/"

# The real libraries, so setup_compiler_cache installs its own trap; only the steps that build or fetch are stubbed.
cat > "${sandbox}/scripts/linux/lib/ci-lane-libs.sh" <<'EOF'
source "${WEB_LANE_REAL_ROOT}/scripts/linux/lib/ci-lane-libs.sh"
eval "_real_$(declare -f antfrastructure_source)"
eval "_real_$(declare -f antfrastructure_path)"
antfrastructure_source() {
  case "$1" in
    */compiler-cache.sh)
      setup_sccache() { :; }
      sccache_s3_drain() { printf 'drained\n' >> "${WEB_LANE_WORK}/drain"; }
      ;;
    */http-readiness.sh)
      wait_for_http() {
        local i
        for ((i = 0; i < 50; i++)); do [ ! -s "${WEB_LANE_WORK}/server.pid" ] || return 0; sleep 0.1; done
        return 1
      }
      ;;
    *) _real_antfrastructure_source "$@" ;;
  esac
}
antfrastructure_path() {
  case "$1" in
    */setup-sqlite3-wasm.sh) printf '%s\n' "${WEB_LANE_WORK}/bin/sccache" ;;
    */flutter_integration_smoke_test.sh) printf '%s\n' "${WEB_LANE_WORK}/smoke.sh" ;;
    *) _real_antfrastructure_path "$@" ;;
  esac
}
omni_ci_enter_workspace() { cd "${WEB_LANE_WORK}/repo" || exit; }
flutter_lane_prepare_env() { :; }
export_toolchain_env() { :; }
check_flutter_launcher_artifacts() { :; }
run_flutter_common_checks() { :; }
EOF
printf 'omni_web_app_build() { :; }\n' > "${sandbox}/scripts/linux/lib/web-app-build.sh"
printf '#!/usr/bin/env bash\nexit "${WEB_LANE_SMOKE_RC:-0}"\n' > "${work}/smoke.sh"
printf '#!/usr/bin/env bash\nexit "${WEB_LANE_BROWSER_RC:-0}"\n' > "${sandbox}/scripts/linux/check-web-browser.sh"
# sccache's --show-stats would start a real server; flutter only answers doctor.
printf '#!/usr/bin/env bash\nexit 0\n' > "${work}/bin/sccache"
cp "${work}/bin/sccache" "${work}/bin/flutter"
cp "${work}/bin/sccache" "${sandbox}/scripts/linux/tests/test-ci-options.sh"
cp "${work}/bin/sccache" "${sandbox}/scripts/linux/tests/test-check-web-browser.sh"
# The smoke server is a sleep that ends on its own, so a missed kill cannot outlive the suite by long.
real_python="$(command -v python3 || echo false)"
printf '#!/usr/bin/env bash\n[ "$1 $2" != "-m http.server" ] || { echo "$$" > %q/server.pid; exec sleep 60; }\nexec %q "$@"\n' \
  "${work}" "${real_python}" > "${work}/bin/python3"
chmod +x "${work}/bin/"* "${work}/smoke.sh"

# run_lane [VAR=value...]: the lane from a clean slate; sets rc.
run_lane() {
  rm -f "${work}/drain" "${work}/server.pid"
  env "$@" PATH="${work}/bin:${PATH}" WEB_LANE_REAL_ROOT="${KATAGLYPHIS_REPO_ROOT}" WEB_LANE_WORK="${work}" \
    bash "${sandbox}/scripts/linux/ci/ci-container-run-web-linux.sh" --arch x64 > "${work}/lane.log" 2>&1 && rc=0 || rc=$?
}

# server_stopped: the smoke server's pid is gone within five seconds of the lane's exit.
server_stopped() {
  local pid i
  pid="$(cat "${work}/server.pid" 2>/dev/null)" || return 1
  for ((i = 0; i < 50; i++)); do
    kill -0 "${pid}" 2>/dev/null || return 0
    sleep 0.1
  done
  return 1
}

t_case "a green lane drains sccache once and stops its smoke server"
run_lane
t_assert_eq 0 "${rc}" "lane exit; log: $(cat "${work}/lane.log")"
t_assert_eq drained "$(cat "${work}/drain" 2>/dev/null)"
t_assert_ok server_stopped

t_case "a failed integration smoke still drains and stops the server"
run_lane WEB_LANE_SMOKE_RC=1
t_assert_eq 1 "${rc}"
t_assert_eq drained "$(cat "${work}/drain" 2>/dev/null)"
t_assert_ok server_stopped

t_case "a failed browser check after the smoke still drains"
run_lane WEB_LANE_BROWSER_RC=1
t_assert_eq 1 "${rc}"
t_assert_eq drained "$(cat "${work}/drain" 2>/dev/null)"

t_summary
