#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
godot_bin="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
report_dir="${TMPDIR:-/private/tmp}/socom-camera-regression"
mkdir -p "$report_dir"

"$godot_bin" --headless --log-file "$report_dir/wall-entry.log" --path "$project_dir" --quit-after 660 -- \
  --automated-test --wall-entry-test --wall-audit-report --transition-audit --clean-hud >/dev/null
"$godot_bin" --headless --log-file "$report_dir/wall-turn.log" --path "$project_dir" --quit-after 730 -- \
  --automated-test --wall-test --wall-turn-test --wall-audit-report --clean-hud >/dev/null
"$godot_bin" --headless --log-file "$report_dir/interior.log" --path "$project_dir" --quit-after 610 -- \
  --automated-test --interior-turn-test --wall-audit-report --clean-hud >/dev/null
"$godot_bin" --headless --log-file "$report_dir/roof.log" --path "$project_dir" --quit-after 180 -- \
  --automated-test --roof-test --downward-aim-test --camera-report --clean-hud >/dev/null
"$godot_bin" --headless --log-file "$report_dir/audit-recorder.log" --path "$project_dir" --quit-after 150 -- \
  --automated-test --movement-test --audit-record-test --clean-hud >/dev/null
"$godot_bin" --headless --log-file "$report_dir/multiplayer-contract.log" --path "$project_dir" --quit-after 90 -- \
  --automated-test --multiplayer-contract-test --clean-hud >/dev/null

for report in "$report_dir"/*.log; do
  if rg -q 'SCRIPT ERROR|Parse Error' "$report"; then
    print -u2 "FAIL: script error in $report"
    exit 1
  fi
done

check_camera_motion() {
  local report="$1"
  local label="$2"
  local maximum_step="$3"
  awk -F, -v label="$label" -v limit="$maximum_step" '
    BEGIN { maximum = 0.0; unreadable = 0; frames = 0; flips = 0; last_transition = -1000 }
    /^WALL_AUDIT/ {
      if (have_previous) {
        dx = $4 - previous_x
        dy = $5 - previous_y
        dz = $6 - previous_z
        step = sqrt(dx * dx + dy * dy + dz * dz)
        if (step > maximum) maximum = step
      }
      previous_x = $4
      previous_y = $5
      previous_z = $6
      have_previous = 1
      frames++
      if ($8 < 0.05 || $8 > 0.95 || $9 < 0.02 || $9 > 0.99) unreadable++
      state = $14
      if (state != previous_state) {
        if (state == state_before_previous && $2 - last_transition <= 15) flips++
        state_before_previous = previous_state
        previous_state = state
        last_transition = $2
      }
    }
    END {
      printf "%s: %d frames, max camera step %.3f m, unreadable %d, state flips %d\n", label, frames, maximum, unreadable, flips
      if (frames == 0 || maximum > limit || unreadable > 0 || flips > 0) exit 1
    }
  ' "$report"
}

check_camera_motion "$report_dir/wall-entry.log" "wall entry/turn/exit" 0.15
check_camera_motion "$report_dir/wall-turn.log" "wall sweep" 0.25
check_camera_motion "$report_dir/interior.log" "tight interior" 0.25

if ! rg -q 'CAMERA_REPORT .*"pitch_deg":-45.0.*"reticle_x":0.5.*"reticle_y":0.5.*"view_pitch_deg":-45.0' "$report_dir/roof.log"; then
  print -u2 "FAIL: rooftop downward aim lost raw pitch or centered reticle"
  exit 1
fi
print "rooftop downward aim: raw -45° pitch and centered reticle"

if ! rg -q 'AUDIT_RECORD_TEST Saved [1-9][0-9]* frames' "$report_dir/audit-recorder.log"; then
  print -u2 "FAIL: camera audit recorder did not save frame telemetry"
  exit 1
fi
print "camera audit recorder: CSV telemetry saved"

if ! rg -q 'MULTIPLAYER_CONTRACT accepted=true camera_state_leak=false' "$report_dir/multiplayer-contract.log"; then
  print -u2 "FAIL: multiplayer aim contract was rejected or leaked camera state"
  exit 1
fi
print "multiplayer contract: authoritative trace accepted, no camera state sent"

print "Camera regression reports: $report_dir"
