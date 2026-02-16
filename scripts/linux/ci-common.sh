#!/usr/bin/env bash
set -euo pipefail

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

  for ((i=1; i<=tries; i++)); do
    echo "Attempt $i to pull container..."
    if timeout 900 docker pull "$CONTAINER_IMAGE"; then
      echo "Successfully pulled container"
      return 0
    fi
    echo "Pull failed, waiting before retry..."
    sleep 30
  done

  echo "Failed to pull container after ${tries} attempts"
  return 1
}
