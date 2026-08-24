#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
godot_bin="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
report_dir="${TMPDIR:-/private/tmp}/socom-multiplayer-lifecycle"
probe_port=$((24141 + ($$ % 1000)))
peer_count="${SOCOM_PROBE_PEERS:-2}"
cycle_count="${SOCOM_PROBE_CYCLES:-2}"
lite_clients="${SOCOM_PROBE_LITE_CLIENTS:-0}"
combat_shots="${SOCOM_PROBE_COMBAT_SHOTS:-0}"
controlled_hits="${SOCOM_PROBE_CONTROLLED_HITS:-0}"
if (( peer_count < 2 || peer_count > 16 )); then
  print -u2 "FAIL: SOCOM_PROBE_PEERS must be between 2 and 16"
  exit 2
fi
if (( cycle_count < 1 || cycle_count > 20 )); then
  print -u2 "FAIL: SOCOM_PROBE_CYCLES must be between 1 and 20"
  exit 2
fi
if (( combat_shots < 0 || combat_shots > 20 )); then
  print -u2 "FAIL: SOCOM_PROBE_COMBAT_SHOTS must be between 0 and 20"
  exit 2
fi
if [[ "$controlled_hits" != "0" && "$controlled_hits" != "1" ]]; then
  print -u2 "FAIL: SOCOM_PROBE_CONTROLLED_HITS must be 0 or 1"
  exit 2
fi
host_log="$report_dir/host.log"
probe_hit_args=()
if [[ "$controlled_hits" == "1" ]]; then
  probe_hit_args+=(--controlled-hits)
fi

mkdir -p "$report_dir"

"$godot_bin" \
  --headless \
  --rendering-method gl_compatibility \
  --log-file "$host_log" \
  --path "$project_dir" \
  --script res://tools/multiplayer_lifecycle_probe.gd -- \
  --role host --port "$probe_port" --expected-peers "$peer_count" \
  --cycles "$cycle_count" --combat-shots "$combat_shots" \
  "${probe_hit_args[@]}" >/dev/null 2>&1 &
host_pid=$!
client_pids=()

cleanup() {
  if kill -0 "$host_pid" 2>/dev/null; then
    kill "$host_pid" 2>/dev/null || true
  fi
  for client_pid in $client_pids; do
    if kill -0 "$client_pid" 2>/dev/null; then
      kill "$client_pid" 2>/dev/null || true
    fi
  done
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

client_index=1
while (( client_index < peer_count )); do
	client_log="$report_dir/client-${client_index}.log"
	client_args=()
	if [[ "$lite_clients" == "1" ]]; then
		client_args+=(--network-probe-lite-client)
	fi
	"$godot_bin" \
    --headless \
    --rendering-method gl_compatibility \
    --log-file "$client_log" \
    --path "$project_dir" \
    --script res://tools/multiplayer_lifecycle_probe.gd -- \
    --role client --port "$probe_port" --expected-peers "$peer_count" \
    --client-index "$client_index" --cycles "$cycle_count" \
    --combat-shots "$combat_shots" \
		"${probe_hit_args[@]}" \
		"${client_args[@]}" >/dev/null 2>&1 &
  client_pids+=("$!")
  (( client_index += 1 ))
done

client_failed=0
for client_pid in $client_pids; do
  if ! wait "$client_pid"; then
    client_failed=1
  fi
done
if ! wait "$host_pid"; then
  print -u2 "FAIL: lifecycle host process exited unsuccessfully"
  client_failed=1
fi
trap - EXIT INT TERM

if ! rg -q "MULTIPLAYER_LIFECYCLE_PROBE HOST PASS" "$host_log"; then
  print -u2 "FAIL: host lifecycle marker missing"
  tail -80 "$host_log"
  exit 1
fi
client_index=1
while (( client_index < peer_count )); do
  client_log="$report_dir/client-${client_index}.log"
  if ! rg -q "MULTIPLAYER_LIFECYCLE_PROBE CLIENT PASS" "$client_log"; then
    print -u2 "FAIL: client $client_index lifecycle marker missing"
    tail -80 "$client_log"
    client_failed=1
  fi
  (( client_index += 1 ))
done
if (( client_failed != 0 )); then
  exit 1
fi

metric_line="$(rg 'MULTIPLAYER_LIFECYCLE_METRIC' "$host_log" | tail -1)"
print "MULTIPLAYER_LIFECYCLE_PROBE PASS peers=$peer_count cycles=$cycle_count lite_clients=$lite_clients combat_shots=$combat_shots controlled_hits=$controlled_hits"
print "$metric_line"
print "Reports: $report_dir"
