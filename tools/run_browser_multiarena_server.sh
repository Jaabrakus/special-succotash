#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
godot_bin="${GODOT_BIN:-}"
if [[ -z "$godot_bin" ]]; then
  for candidate in \
    /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
    /Applications/Godot.app/Contents/MacOS/Godot \
    /Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot; do
    if [[ -x "$candidate" ]]; then
      godot_bin="$candidate"
      break
    fi
  done
fi
if [[ -z "$godot_bin" || ! -x "$godot_bin" ]]; then
  print -u2 "FAIL: set GODOT_BIN to an executable Godot 4 binary"
  exit 2
fi

server_port="${SOCOM_SERVER_PORT:-14141}"
if [[ "$server_port" != <1-> || "$server_port" -lt 1 || "$server_port" -gt 65535 ]]; then
  print -u2 "FAIL: SOCOM_SERVER_PORT must be between 1 and 65535"
  exit 2
fi

print "Starting SOCOM-141: WebSocket, 32 players, eight isolated 2v2 arenas, port $server_port"
exec "$godot_bin" \
  --headless \
  --audio-driver Dummy \
  --rendering-method gl_compatibility \
  --log-file "${TMPDIR:-/private/tmp}/socom-141-dedicated-server.log" \
  --path "$project_dir" \
  res://multiplayer_slice.tscn -- \
  --dedicated-server \
  --tournament-32 \
  --mp-transport=websocket \
  "--mp-port=$server_port"
