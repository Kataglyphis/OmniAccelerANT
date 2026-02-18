#!/usr/bin/env bash

set -euo pipefail

is_in_docker() {
  [[ -f "/.dockerenv" ]] && return 0
  [[ -n "${IN_DOCKER:-}" ]] && return 0
  return 1
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) echo "x64" ;;
  esac
}

arch_to_platform() {
  case "${1:?arch}" in
    x64) echo "linux/amd64" ;;
    arm64) echo "linux/arm64" ;;
    *) echo "linux/amd64" ;;
  esac
}

docker_pull_with_retry() {
  local image="${1:?image}"
  local platform="${2:-}"
  local tries="${3:-3}"

  for ((i=1; i<=tries; i++)); do
    echo "Attempt $i to pull container..."
    if [[ -n "$platform" ]]; then
      if timeout 900 docker pull --platform "$platform" "$image"; then
        echo "Successfully pulled container"
        return 0
      fi
    else
      if timeout 900 docker pull "$image"; then
        echo "Successfully pulled container"
        return 0
      fi
    fi
    echo "Pull failed, waiting before retry..."
    sleep 30
  done

  echo "Failed to pull container after ${tries} attempts" >&2
  return 1
}

run_docker_workspace_script() {
  local image="${1:?image}"
  local platform="${2:-}"
  local repo_root="${3:?repo_root}"
  local script_path_in_workspace="${4:?script_path_in_workspace}"

  shift 4
  local extra_env=()
  while (( "$#" )); do
    extra_env+=("-e" "$1")
    shift
  done

  local docker_args=(
    "--rm"
    "--mount" "type=bind,source=${repo_root},target=/workspace"
    "-w" "/workspace"
  )

  if [[ -n "$platform" ]]; then
    docker_args+=("--platform" "$platform")
  fi

  docker run "${docker_args[@]}" \
    "${extra_env[@]}" \
    "$image" \
    bash -lc "bash /workspace/${script_path_in_workspace}"
}
