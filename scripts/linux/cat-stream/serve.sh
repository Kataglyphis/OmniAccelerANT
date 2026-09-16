#!/usr/bin/env bash
# Serves the release web build over HTTPS with the COOP/COEP headers the
# Stream page needs, and proxies /webrtc-ws to the kataglyphis_cat_webrtc
# producer's plain-WebSocket signalling server.
#
# Why a proxy terminates the TLS: the Stream page needs cross-origin isolation
# for its SharedArrayBuffer, which browsers grant only on HTTPS (or localhost);
# and the GStreamer signalling server's rustls refuses a self-signed
# certificate used as an end-entity ("CaUsedAsEndEntity"). Doing TLS here
# solves both and keeps the producer on plain WS.
#
# Usage:
#   scripts/linux/cat-stream/serve.sh [--port 8444] [--producer-host 127.0.0.1]
#                                     [--producer-port 8443]
#                                     [--web-root build/web]
#                                     [--state-dir build/cat-stream]
#
# The producer has to listen on --producer-host:--producer-port (its
# --listen-port) and the web build's signalingServerUrl has to be
# /webrtc-ws (the default) or an absolute wss:// URL pointing at this
# server. Use --producer-host to front a producer on another board (e.g. a
# Pi Zero 2 W or a RISC-V SoC) without deploying the web build there; give
# each concurrent instance its own --state-dir (config, pid, TLS, logs).
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../.." && pwd)"

port=8444
producer_host=127.0.0.1
producer_port=8443
web_root="${repo_root}/build/web"
state_dir="${repo_root}/build/cat-stream"

while [ $# -gt 0 ]; do
  case "$1" in
    --port) port="${2:?--port needs a value}"; shift 2 ;;
    --producer-host) producer_host="${2:?--producer-host needs a value}"; shift 2 ;;
    --producer-port) producer_port="${2:?--producer-port needs a value}"; shift 2 ;;
    --web-root) web_root="${2:?--web-root needs a value}"; shift 2 ;;
    --state-dir) state_dir="${2:?--state-dir needs a value}"; shift 2 ;;
    -h|--help)
      printf 'usage: %s [--port N] [--producer-host HOST] [--producer-port N] [--web-root DIR] [--state-dir DIR]\n' "$0"
      exit 0
      ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

command -v nginx >/dev/null 2>&1 || {
  printf 'nginx not found — install it (e.g. apt install nginx)\n' >&2
  exit 1
}
[ -f "${web_root}/index.html" ] || {
  printf 'no web build at %s — run "flutter build web --release" first\n' "${web_root}" >&2
  exit 1
}

# nginx resolves a relative -c against the -p prefix, which would double the
# path; make the state dir absolute up front.
mkdir -p "${state_dir}"
state_dir="$(cd -- "${state_dir}" && pwd)"

tls_dir="${state_dir}/tls"
mkdir -p "${tls_dir}" \
  "${state_dir}/client_body" "${state_dir}/proxy" "${state_dir}/fastcgi" \
  "${state_dir}/uwsgi" "${state_dir}/scgi"

# A certificate with only a CN and no subjectAltName is rejected outright by
# every current browser (Chrome dropped the CN fallback in 58), which is the
# difference between "click through the warning once" and "this page cannot be
# reached" — and on a phone the click-through is the whole bring-up path. So the
# cert carries a SAN covering every name this server can plausibly be reached
# by: localhost, the loopback literals, the host's name and its LAN addresses.
# An existing CN-only cert is regenerated rather than kept, because the guard
# below is a cache and a cached broken cert is indistinguishable from a broken
# server.
cert_has_san() {
  [ -f "${tls_dir}/cert.pem" ] || return 1
  openssl x509 -in "${tls_dir}/cert.pem" -noout -ext subjectAltName \
    >/dev/null 2>&1
}

if ! cert_has_san; then
  command -v openssl >/dev/null 2>&1 || {
    printf 'openssl not found and no usable certificate in %s — install openssl\n' "${tls_dir}" >&2
    exit 1
  }
  if [ -f "${tls_dir}/cert.pem" ]; then
    printf 'certificate in %s has no subjectAltName — regenerating\n' "${tls_dir}" >&2
  else
    printf 'generating a self-signed certificate in %s\n' "${tls_dir}" >&2
  fi

  # `hostname -I` is Linux-only and prints every global address, space
  # separated; it is absent on some minimal images, hence the `|| true` and the
  # unconditional loopback entries. Duplicates in a SAN list are harmless.
  san="DNS:localhost,DNS:$(hostname 2>/dev/null || echo cat-stream),IP:127.0.0.1,IP:::1"
  for addr in $(hostname -I 2>/dev/null || true); do
    case "${addr}" in
      *:*) san="${san},IP:${addr}" ;;
      *.*) san="${san},IP:${addr}" ;;
    esac
  done

  # -addext needs openssl 1.1.1 (bullseye ships it). The fallback keeps a very
  # old host working rather than failing the whole demo over a warning-level
  # nicety.
  openssl req -x509 -newkey rsa:2048 -sha256 -days 825 -nodes \
    -keyout "${tls_dir}/key.pem" -out "${tls_dir}/cert.pem" \
    -subj "/CN=cat-stream" -addext "subjectAltName=${san}" >/dev/null 2>&1 ||
    openssl req -x509 -newkey rsa:2048 -sha256 -days 825 -nodes \
      -keyout "${tls_dir}/key.pem" -out "${tls_dir}/cert.pem" \
      -subj "/CN=cat-stream" >/dev/null 2>&1
fi

mime_include=""
if [ -f /etc/nginx/mime.types ]; then
  mime_include="include /etc/nginx/mime.types;"
fi

cat > "${state_dir}/nginx.conf" <<EOF
worker_processes 1;
pid ${state_dir}/nginx.pid;
error_log ${state_dir}/error.log warn;

events { worker_connections 128; }

http {
  ${mime_include}
  # Both extensions are declared here because the host's mime.types cannot be
  # trusted to carry them: nginx 1.18 (Debian/Pi OS bullseye, Ubuntu 22.04) has
  # neither, default_type below then makes them application/octet-stream, and
  # both the dynamic import() of main.dart.mjs and compileStreaming() of
  # main.dart.wasm refuse that — a blank page naming no cause. Harmless on a
  # newer nginx, which logs "duplicate extension" at warn and continues.
  # Symptoms and the curl check: docs/source/camera-streaming.md, Troubleshooting.
  # NB: no backticks in this comment — the heredoc is unquoted, so backticks in
  # prose are command substitution.
  types {
    application/javascript mjs;
    application/wasm        wasm;
  }
  default_type application/octet-stream;
  access_log ${state_dir}/access.log;
  client_body_temp_path ${state_dir}/client_body;
  proxy_temp_path ${state_dir}/proxy;
  fastcgi_temp_path ${state_dir}/fastcgi;
  uwsgi_temp_path ${state_dir}/uwsgi;
  scgi_temp_path ${state_dir}/scgi;

  server {
    listen ${port} ssl;
    ssl_certificate ${tls_dir}/cert.pem;
    ssl_certificate_key ${tls_dir}/key.pem;
    root ${web_root};

    # The Stream page checks for cross-origin isolation before using its
    # SharedArrayBuffer-backed storage.
    add_header Cross-Origin-Opener-Policy same-origin always;
    add_header Cross-Origin-Embedder-Policy require-corp always;

    location /webrtc-ws {
      proxy_pass http://${producer_host}:${producer_port};
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection "Upgrade";
      proxy_read_timeout 86400s;
    }

    location / {
      try_files \$uri \$uri/ /index.html;
    }
  }
}
EOF

printf 'serving %s on https://<host>:%s/ (self-signed — accept the warning)\n' "${web_root}" "${port}"
printf 'proxying /webrtc-ws to the producer on %s:%s\n' "${producer_host}" "${producer_port}"
exec nginx -c "${state_dir}/nginx.conf" -p "${state_dir}" -g 'daemon off;'
