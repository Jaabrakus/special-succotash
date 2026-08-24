#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
godot_bin="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
report_dir="${TMPDIR:-/private/tmp}/socom-multiplayer-lifecycle"
probe_port=$((24141 + ($$ % 1000)))
host_log="$report_dir/host.log"
client_log="$report_dir/client.log"

mkdir -p "$report_dir"

"$godot_bin" \
  --headless \
  --rendering-method gl_compatibility \
  --log-file "$host_log" \
  --path "$project_dir" \
  --script res://tools/multiplayer_lifecycle_probe.gd -- \
  --role host --port "$probe_port" >/dev/null 2>&1 &
host_pid=$!

cleanup() {
  if kill -0 "$host_pid" 2>/dev/null; then
    kill "$host_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

ready=0
for _attempt in {1..100}; do
  if rg -q "MULTIPLAYER_LIFECYCLE HOST_READY" "$host_log" 2>/dev/null; then
    ready=1
    break
  fi
  if ! kill -0 "$host_pid" 2>/dev/null; then
    break
  fi
  sleep 0.05
done
if [[ "$ready" != "1" ]]; then
  print -u2 "FAIL: lifecycle host did not become ready"
  tail -80 "$host_log" 2>/dev/null || true
  exit 1
fi

"$godot_bin" \
  --headless \
  --rendering-method gl_compatibility \
  --log-file "$client_log" \
  --path "$project_dir" \
  --script res://tools/multiplayer_lifecycle_probe.gd -- \
  --role client --port "$probe_port" >/dev/null 2>&1

wait "$host_pid"
trap - EXIT INT TERM

if ! rg -q "MULTIPLAYER_LIFECYCLE_PROBE HOST PASS" "$host_log"; then
  print -u2 "FAIL: host lifecycle marker missing"
  tail -80 "$host_log"
  exit 1
fi
if ! rg -q "MULTIPLAYER_LIFECYCLE_PROBE CLIENT PASS" "$client_log"; then
  print -u2 "FAIL: client lifecycle marker missing"
  tail -80 "$client_log"
  exit 1
fi

print "MULTIPLAYER_LIFECYCLE_PROBE PASS"
print "Reports: $report_dir"
