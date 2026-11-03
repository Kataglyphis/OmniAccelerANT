#!/usr/bin/env bash
# Sourced first by every ObservANT entry script; the caller's location decides, because the checkout can sit anywhere.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[1]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../.." && pwd)"
export script_dir repo_root
