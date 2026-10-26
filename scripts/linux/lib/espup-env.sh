#!/usr/bin/env bash

omni_espup_environment() {
    local espup_home="${ESPUP_HOME:-${HOME}/.cache/kataglyphis-esp}"
    if [[ -f "${espup_home}/export.sh" ]]; then
        # shellcheck disable=SC1091
        source "${espup_home}/export.sh" || return $?
        export RUSTUP_HOME="${espup_home}/rustup"
        export CARGO_HOME="${espup_home}/cargo"
        export PATH="${espup_home}/cargo/bin:${espup_home}/bin:${PATH}"
    elif [[ -f "${HOME}/export-esp.sh" ]]; then
        # shellcheck disable=SC1091
        source "${HOME}/export-esp.sh" || return $?
    else
        echo "no espup environment; run 'espup install --targets esp32s3' first" >&2
        return 2
    fi
}
