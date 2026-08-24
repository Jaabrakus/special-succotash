#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
soak_cycles="${SOCOM_SOAK_CYCLES:-5}"

if (( soak_cycles < 1 || soak_cycles > 20 )); then
	print -u2 "FAIL: SOCOM_SOAK_CYCLES must be between 1 and 20"
	exit 2
fi

# Lightweight clients exercise real ENet connections and the complete lobby,
# spawn, snapshot, round, teardown, and rematch protocol. They intentionally
# omit client rendering so all 16 peers can run on one workstation without 256
# animation rigs obscuring the listen-server measurement.
SOCOM_PROBE_PEERS=16 \
SOCOM_PROBE_CYCLES="$soak_cycles" \
SOCOM_PROBE_LITE_CLIENTS=1 \
exec "$project_dir/tools/run_multiplayer_lifecycle_probe.sh"
