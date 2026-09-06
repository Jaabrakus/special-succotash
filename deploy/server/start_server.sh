#!/bin/sh
set -eu

server_port="${PORT:-${SOCOM_SERVER_PORT:-10000}}"
case "$server_port" in
  ''|*[!0-9]*)
    echo "FAIL: PORT must be an integer from 1 through 65535" >&2
    exit 2
    ;;
esac
if [ "$server_port" -lt 1 ] || [ "$server_port" -gt 65535 ]; then
  echo "FAIL: PORT must be an integer from 1 through 65535" >&2
  exit 2
fi

if [ -z "${SOCOM_SUPABASE_SERVER_KEY:-}" ]; then
  echo "FAIL: SOCOM_SUPABASE_SERVER_KEY is not configured" >&2
  exit 2
fi
if [ -z "${SOCOM_RULESET_ID:-}" ]; then
  echo "FAIL: SOCOM_RULESET_ID is not configured" >&2
  exit 2
fi

public_address="${SOCOM_SERVER_PUBLIC_ADDRESS:-}"
if [ -z "$public_address" ] && [ -n "${RENDER_EXTERNAL_HOSTNAME:-}" ]; then
  public_address="wss://${RENDER_EXTERNAL_HOSTNAME}"
fi
if [ -z "$public_address" ] && [ -n "${RENDER_EXTERNAL_URL:-}" ]; then
  case "$RENDER_EXTERNAL_URL" in
    https://*) public_address="wss://${RENDER_EXTERNAL_URL#https://}" ;;
  esac
fi
if [ -z "$public_address" ]; then
  echo "FAIL: set SOCOM_SERVER_PUBLIC_ADDRESS to the public wss:// endpoint" >&2
  exit 2
fi
case "$public_address" in
  wss://*) ;;
  *)
    echo "FAIL: SOCOM_SERVER_PUBLIC_ADDRESS must use wss://" >&2
    exit 2
    ;;
esac

export SOCOM_SERVER_PUBLIC_ADDRESS="$public_address"
export SOCOM_SERVER_PORT="$server_port"
export SOCOM_INTERNAL_PORT=17777
export SOCOM_SERVER_BIND_ADDRESS=127.0.0.1

echo "Starting SOCOM-141 dedicated server on port $server_port"
echo "Advertising secure WebSocket endpoint $public_address"

exec node /srv/socom/deploy/server/http_gateway.mjs /opt/godot/godot \
  --headless \
  --audio-driver Dummy \
  --rendering-method gl_compatibility \
  --log-file /tmp/socom-141-server.log \
  --path /srv/socom \
  res://multiplayer_slice.tscn -- \
  --dedicated-server \
  --tournament-32 \
  --mp-transport=websocket \
  "--mp-port=$SOCOM_INTERNAL_PORT"
