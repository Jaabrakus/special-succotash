#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"

# One client deliberately drops during the first live round, reconnects with a
# new ENet peer identity as a safe spectator, then joins the next full round.
SOCOM_PROBE_PEERS="${SOCOM_RECONNECT_PEERS:-16}" \
SOCOM_PROBE_CYCLES="${SOCOM_RECONNECT_CYCLES:-2}" \
SOCOM_PROBE_LITE_CLIENTS=1 \
SOCOM_PROBE_COMBAT_SHOTS=0 \
SOCOM_PROBE_CONTROLLED_HITS=0 \
SOCOM_PROBE_RECONNECT=1 \
exec "$project_dir/tools/run_multiplayer_lifecycle_probe.sh"
