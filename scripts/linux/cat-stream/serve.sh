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
#   scripts/linux/cat-stream/serve.sh [--port 8444] [--producer-port 8443]
#                                     [--web-root build/web]
#
# The producer has to listen on --producer-port (its --listen-port) and the
# web build's signalingServerUrl has to be /webrtc-ws (the default) or an
# absolute wss:// URL pointing at this server.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/../../.." && pwd)"

port=8444
producer_port=8443
web_root="${repo_root}/build/web"

while [ $# -gt 0 ]; do
  case "$1" in
    --port) port="${2:?--port needs a value}"; shift 2 ;;
    --producer-port) producer_port="${2:?--producer-port needs a value}"; shift 2 ;;
    --web-root) web_root="${2:?--web-root needs a value}"; shift 2 ;;
    -h|--help)
      printf 'usage: %s [--port N] [--producer-port N] [--web-root DIR]\n' "$0"
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

state_dir="${repo_root}/build/cat-stream"
tls_dir="${state_dir}/tls"
mkdir -p "${tls_dir}" \
  "${state_dir}/client_body" "${state_dir}/proxy" "${state_dir}/fastcgi" \
  "${state_dir}/uwsgi" "${state_dir}/scgi"

if [ ! -f "${tls_dir}/cert.pem" ]; then
  command -v openssl >/dev/null 2>&1 || {
    printf 'openssl not found and no certificate in %s — install openssl\n' "${tls_dir}" >&2
    exit 1
  }
  printf 'generating a self-signed certificate in %s\n' "${tls_dir}" >&2
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
      proxy_pass http://127.0.0.1:${producer_port};
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
printf 'proxying /webrtc-ws to the producer on 127.0.0.1:%s\n' "${producer_port}"
exec nginx -c "${state_dir}/nginx.conf" -p "${state_dir}" -g 'daemon off;'
