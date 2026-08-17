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
"$godot_bin" --headless --log-file "$report_dir/wall-follow.log" --path "$project_dir" --quit-after 650 -- \
  --automated-test --wall-follow-test --wall-audit-report --clean-hud >/dev/null
"$godot_bin" --headless --log-file "$report_dir/interior.log" --path "$project_dir" --quit-after 610 -- \
  --automated-test --interior-turn-test --wall-audit-report --camera-report --clean-hud >/dev/null
"$godot_bin" --headless --log-file "$report_dir/roof.log" --path "$project_dir" --quit-after 180 -- \
  --automated-test --roof-test --downward-aim-test --camera-report --clean-hud >/dev/null
"$godot_bin" --headless --log-file "$report_dir/audit-recorder.log" --path "$project_dir" --quit-after 150 -- \
  --automated-test --movement-test --audit-record-test --clean-hud >/dev/null
"$godot_bin" --headless --log-file "$report_dir/multiplayer-contract.log" --path "$project_dir" --quit-after 90 -- \
  --automated-test --multiplayer-contract-test --clean-hud >/dev/null
"$godot_bin" --headless --log-file "$report_dir/multiplayer-wall-contract.log" --path "$project_dir" --quit-after 90 -- \
  --automated-test --wall-follow-test --multiplayer-contract-test --clean-hud >/dev/null

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
    BEGIN { maximum = 0.0; unreadable = 0; horizontal_lost = 0; tether_lost = 0; frames = 0; flips = 0; last_transition = -1000; position_frozen = 0; maximum_position_frozen = 0; view_frozen = 0; maximum_view_frozen = 0 }
    /^WALL_AUDIT/ {
      if (have_previous) {
        dx = $4 - previous_x
        dy = $5 - previous_y
        dz = $6 - previous_z
        step = sqrt(dx * dx + dy * dy + dz * dz)
        if (step > maximum) maximum = step
        yaw_step = $3 - previous_yaw
        if (yaw_step < 0) yaw_step = -yaw_step
        if (yaw_step > 0.05 && $10 == 1) {
          if (step < 0.003) position_frozen++
          else position_frozen = 0
          if (position_frozen > maximum_position_frozen) maximum_position_frozen = position_frozen
          view_step = $16 - previous_view_yaw
          if (view_step < 0) view_step = -view_step
          if (view_step > 180) view_step = 360 - view_step
          if (view_step < 0.05) view_frozen++
          else view_frozen = 0
          if (view_frozen > maximum_view_frozen) maximum_view_frozen = view_frozen
        }
      }
      previous_x = $4
      previous_y = $5
      previous_z = $6
      previous_yaw = $3
      previous_view_yaw = $16
      have_previous = 1
      frames++
      near_body = $15 + 0
      if (!near_body && ($8 < 0.05 || $8 > 0.95 || $9 < 0.02 || $9 > 0.99)) unreadable++
      # Near-body cropping may spend vertical silhouette, never horizontal
      # ownership. This catches a legal lens that remains stuck on an old wall
      # while the operator slides out of the shot.
      if ($8 < 0.18 || $8 > 0.82) horizontal_lost++
      if ($7 > 5.50) tether_lost++
      state = $14
      if (state != previous_state) {
        if (state == state_before_previous && $2 - last_transition <= 15) flips++
        state_before_previous = previous_state
        previous_state = state
        last_transition = $2
      }
    }
    END {
      printf "%s: %d frames, max camera step %.3f m, unreadable %d, horizontal lost %d, tether lost %d, state flips %d, max lens contact %d, max view freeze %d\n", label, frames, maximum, unreadable, horizontal_lost, tether_lost, flips, maximum_position_frozen, maximum_view_frozen
      if (frames == 0 || maximum > limit || unreadable > 0 || horizontal_lost > 0 || tether_lost > 0 || flips > 0 || maximum_view_frozen > 2) exit 1
    }
  ' "$report"
}

check_camera_motion "$report_dir/wall-entry.log" "wall entry/turn/exit" 0.15
check_camera_motion "$report_dir/wall-turn.log" "wall sweep" 0.25
check_camera_motion "$report_dir/wall-follow.log" "player leaves wall" 0.25
check_camera_motion "$report_dir/interior.log" "tight interior" 0.25

if rg -P -q '"virtual_wall_occluder":"(?!CLEAR)' "$report_dir/wall-entry.log"; then
  print -u2 "FAIL: camera recovery concealed solid wall geometry"
  exit 1
fi
print "wall visibility: solid geometry remained opaque during camera recovery"

if ! awk -F, '/^WALL_AUDIT/ && $10 == 1 { found = 1 } END { exit !found }' "$report_dir/wall-follow.log"; then
  print -u2 "FAIL: player-leaves-wall scenario never entered camera collision"
  exit 1
fi
print "player leaves wall: began physically compressed, then retained player tether"

for intent_report in \
  "$report_dir/wall-entry.log" \
  "$report_dir/wall-turn.log" \
  "$report_dir/wall-follow.log" \
  "$report_dir/interior.log"; do
  if rg -P -q '"reticle_dynamic_amount":(?!0\.0)|"reticle_x":(?!0\.5)|"reticle_y":(?!0\.5)' "$intent_report"; then
    print -u2 "FAIL: collision or environment state moved the authoritative reticle"
    exit 1
  fi
done
print "aim ownership: reticle remained exactly centered through every wall state"

if ! rg -q 'CAMERA_REPORT .*"pitch_deg":-2.0.*"reticle_x":0.5.*"reticle_y":0.5.*"view_pitch_deg":-2.0' "$report_dir/interior.log"; then
  print -u2 "FAIL: interior state redirected raw pitch or moved the reticle"
  exit 1
fi
print "interior aim: raw pitch preserved without environment bias"

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

if ! rg -q 'MULTIPLAYER_CONTRACT accepted=true camera_state_leak=false replay=STALE_SEQUENCE spoof=DIRECTION_ANGLE_MISMATCH future=FUTURE_TICK' "$report_dir/multiplayer-contract.log"; then
  print -u2 "FAIL: multiplayer aim contract accepted invalid input, rejected valid input, or leaked camera state"
  exit 1
fi
if ! rg -q 'MULTIPLAYER_CONTRACT accepted=true camera_state_leak=false replay=STALE_SEQUENCE spoof=DIRECTION_ANGLE_MISMATCH future=FUTURE_TICK' "$report_dir/multiplayer-wall-contract.log"; then
  print -u2 "FAIL: close-wall camera changed authoritative multiplayer aim validation"
  exit 1
fi
print "multiplayer contract: open and close-wall traces accepted; replay, spoof and future-tick input rejected; no camera state sent"

print "Camera regression reports: $report_dir"
