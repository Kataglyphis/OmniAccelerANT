#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/docker-runner.sh"
source "$SCRIPT_DIR/lib/container-steps.sh"

require_ci_env() {
  : "${CONTAINER_IMAGE:?CONTAINER_IMAGE is required}"
  : "${MATRIX_ARCH:?MATRIX_ARCH is required (x64|arm64)}"
  : "${FLUTTER_VERSION:?FLUTTER_VERSION is required}"
  : "${FLUTTER_DIR:?FLUTTER_DIR is required}"
  : "${APP_NAME:?APP_NAME is required}"
}

ci_detect_platform() {
  if [[ -n "${CONTAINER_PLATFORM:-}" ]]; then
    echo "${CONTAINER_PLATFORM}"
    return
  fi
  arch_to_platform "${MATRIX_ARCH}"
}

pull_container_with_retry() {
  local tries="${1:-3}"
  docker_pull_with_retry "${CONTAINER_IMAGE}" "$(ci_detect_platform)" "$tries"
}

run_container() {
  local command_script="${1:?container command script required}"
  local repo_root
  repo_root="$(pwd)"

  docker run --rm \
    --platform "$(ci_detect_platform)" \
    --mount "type=bind,source=${repo_root},target=/workspace" \
    -w /workspace \
    -e MATRIX_ARCH \
    -e FLUTTER_VERSION \
    -e FLUTTER_DIR \
    -e APP_NAME \
    -e CI=true \
    "${CONTAINER_IMAGE}" \
    bash -lc "$command_script"
}
