#!/usr/bin/env bash
set -euo pipefail

_ci_common_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/containerhub.sh
source "${_ci_common_dir}/lib/containerhub.sh"

# info/warn/err + retry() come from ContainerHub.
containerhub_source linux/scripts/01-core/logging.sh

require_ci_env() {
  : "${CONTAINER_IMAGE:=ghcr.io/kataglyphis/kataglyphis_beschleuniger:latest}"
  : "${WORKSPACE_DIR:=/workspace}"
  : "${MATRIX_PLATFORM:?MATRIX_PLATFORM is required}"
  : "${MATRIX_ARCH:?MATRIX_ARCH is required}"
  : "${FLUTTER_VERSION:?FLUTTER_VERSION is required}"
  : "${FLUTTER_DIR:=/workspace/flutter}"
  : "${APP_NAME:?APP_NAME is required}"
}

run_container() {
  local container_script="$1"

  docker run --rm \
    --platform "$MATRIX_PLATFORM" \
    -v "${GITHUB_WORKSPACE:-$PWD}:/workspace" \
    -w "$WORKSPACE_DIR" \
    -e FLUTTER_VERSION="$FLUTTER_VERSION" \
    -e FLUTTER_DIR="$FLUTTER_DIR" \
    -e MATRIX_ARCH="$MATRIX_ARCH" \
    -e APP_NAME="$APP_NAME" \
    "$CONTAINER_IMAGE" \
    bash -lc "$container_script"
}

pull_container_with_retry() {
  local tries="${1:-3}"

  # ContainerHub's retry(): same cadence as the loop it replaces (N attempts,
  # 30s apart, each pull bounded by `timeout` so a hung pull actually retries
  # instead of stalling until the job limit).
  retry "$tries" 30 "docker pull ${CONTAINER_IMAGE}" \
    timeout 900 docker pull "$CONTAINER_IMAGE"
}
