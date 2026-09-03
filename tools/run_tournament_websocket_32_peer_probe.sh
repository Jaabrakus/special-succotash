#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE

project_dir="${0:A:h:h}"
godot_bin="${GODOT_BIN:-}"
if [[ -z "$godot_bin" ]]; then
  for candidate in \
    /Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
    /Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
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

report_dir="${TMPDIR:-/private/tmp}/socom-tournament-websocket-32-$$"
base_probe_port=$((25141 + ($$ % 19000)))
probe_port="$base_probe_port"
host_log=""
completion_directory="$report_dir/all-clients-validated"
mkdir -p "$report_dir"

engine_args=(
  --headless
  --rendering-method gl_compatibility
  --path "$project_dir"
  --script res://tools/tournament_websocket_32_peer_probe.gd
)
probe_args=(
  --tournament-32
  --mp-transport=websocket
)

host_pid=""
client_pids=()
watchdog_pid=""
completion_watcher_pid=""

cleanup() {
  if [[ -n "$watchdog_pid" ]] && kill -0 "$watchdog_pid" 2>/dev/null; then
    kill "$watchdog_pid" 2>/dev/null || true
  fi
  if [[ -n "$completion_watcher_pid" ]] && kill -0 "$completion_watcher_pid" 2>/dev/null; then
    kill "$completion_watcher_pid" 2>/dev/null || true
  fi
  if [[ -n "$host_pid" ]] && kill -0 "$host_pid" 2>/dev/null; then
    kill "$host_pid" 2>/dev/null || true
  fi
  for client_pid in $client_pids; do
    if kill -0 "$client_pid" 2>/dev/null; then
      kill "$client_pid" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT INT TERM

host_ready=0
for port_attempt in {0..15}; do
  probe_port=$((base_probe_port + port_attempt * 137))
  host_log="$report_dir/host-${probe_port}.log"
  "$godot_bin" \
    "${engine_args[@]}" \
    --log-file "$host_log" -- \
    "${probe_args[@]}" \
    --role host --port "$probe_port" \
    --completion-directory "$completion_directory" >/dev/null 2>&1 &
  host_pid=$!

  for _attempt in {1..100}; do
    if rg -q "TOURNAMENT_WS32 HOST_LISTENING" "$host_log" 2>/dev/null; then
      host_ready=1
      break
    fi
    if ! kill -0 "$host_pid" 2>/dev/null; then
      break
    fi
    sleep 0.1
  done
  if [[ "$host_ready" == "1" ]]; then
    break
  fi

  wait "$host_pid" 2>/dev/null || true
  host_pid=""
  if ! rg -q "host could not bind WebSocket port" "$host_log" 2>/dev/null; then
    break
  fi
done
if [[ "$host_ready" != "1" ]]; then
  print -u2 "FAIL: tournament WebSocket host did not become ready"
  tail -100 "$host_log" 2>/dev/null || true
  exit 1
fi

# Give the native WebSocket listener one fixed interval before 31 independent
# canonical clients begin their admission handshakes.
sleep 1
for client_index in {1..31}; do
  client_log="$report_dir/client-${client_index}.log"
  "$godot_bin" \
    "${engine_args[@]}" \
    --log-file "$client_log" -- \
    "${probe_args[@]}" \
    --role client --port "$probe_port" --client-index "$client_index" \
    --completion-directory "$completion_directory" \
    --network-probe-lite-client >/dev/null 2>&1 &
  client_pids+=("$!")
  # Avoid a synchronized import/connection burst on one development machine.
  sleep 0.12
done

# Release the host only when every independent client has logged its complete
# roster/map-scope assertion. A directory is used as the cross-process signal
# so no probe process needs an extra RPC outside the production wire contract.
(
  for _attempt in {1..1800}; do
    pass_count="$(awk '
      /TOURNAMENT_WS32 CLIENT PASS/ {seen[FILENAME] = 1}
      END {for (file in seen) count += 1; print count + 0}
    ' "$report_dir"/client-*.log)"
    if [[ "$pass_count" == "31" ]]; then
      mkdir "$completion_directory"
      exit 0
    fi
    sleep 0.1
  done
  print -u2 "TOURNAMENT_WS32 COMPLETION_BARRIER_TIMEOUT reports=$report_dir"
  exit 1
) &
completion_watcher_pid=$!

# The in-engine probes have bounded waits. This outer guard also makes a native
# crash or a wedged process return a diagnostic instead of hanging CI.
(
  sleep 240
  print -u2 "TOURNAMENT_WS32 WATCHDOG_TIMEOUT reports=$report_dir"
  kill "$host_pid" 2>/dev/null || true
  for client_pid in $client_pids; do
    kill "$client_pid" 2>/dev/null || true
  done
) &
watchdog_pid=$!

process_failed=0
for client_pid in $client_pids; do
  if ! wait "$client_pid"; then
    process_failed=1
  fi
done
if ! wait "$host_pid"; then
  process_failed=1
fi
if ! wait "$completion_watcher_pid"; then
  process_failed=1
fi
completion_watcher_pid=""
if kill -0 "$watchdog_pid" 2>/dev/null; then
  kill "$watchdog_pid" 2>/dev/null || true
fi
watchdog_pid=""
trap - EXIT INT TERM

if ! rg -q "TOURNAMENT_WS32 HOST PASS" "$host_log"; then
  print -u2 "FAIL: authoritative 32-peer host marker is missing"
  tail -120 "$host_log"
  exit 1
fi
if ! rg -q "TOURNAMENT_WS32 HOST_CLIENTS_VALIDATED count=31" "$host_log"; then
  print -u2 "FAIL: authoritative host did not observe all 31 scoped client results"
  tail -120 "$host_log"
  exit 1
fi
if ! rg -q "TOURNAMENT_WS32 HOST_TRANSPORT_CLOSED" "$host_log"; then
  print -u2 "FAIL: authoritative host did not close its WebSocket transport"
  tail -120 "$host_log"
  exit 1
fi

for client_index in {1..31}; do
  client_log="$report_dir/client-${client_index}.log"
  if ! rg -q "TOURNAMENT_WS32 CLIENT PASS" "$client_log"; then
    print -u2 "FAIL: client $client_index did not prove its assigned arena scope"
    tail -100 "$client_log"
    process_failed=1
  fi
  if ! rg -q "TOURNAMENT_WS32 CLIENT_SERVER_CLOSED" "$client_log"; then
    print -u2 "FAIL: client $client_index did not observe the coordinated server close"
    tail -100 "$client_log"
    process_failed=1
  fi
done

# Arena zero contains the listen host and three remote clients. Every other
# arena contains four remote clients. Validate that all eight client-side map
# assignments appeared, not merely 31 generic pass markers.
for arena_id in {0..7}; do
  expected_count=4
  if [[ "$arena_id" == "0" ]]; then
    expected_count=3
  fi
  actual_count="$(awk -v arena="$arena_id" '
    /TOURNAMENT_WS32 CLIENT PASS/ && index($0, "arena=" arena " ") {count += 1}
    END {print count + 0}
  ' "$report_dir"/client-*.log)"
  if [[ "$actual_count" != "$expected_count" ]]; then
    print -u2 "FAIL: arena $arena_id has $actual_count scoped clients; expected $expected_count"
    process_failed=1
  fi
done

if (( process_failed != 0 )); then
  print -u2 "FAIL: one or more 32-peer tournament processes failed"
  print -u2 "Reports: $report_dir"
  exit 1
fi

print "TOURNAMENT_WEBSOCKET_32_PEER_PROBE PASS transport=websocket peers=32 pairs=16 arenas=8 server_map_roots=8 client_map_roots=1"
print "Reports: $report_dir"
