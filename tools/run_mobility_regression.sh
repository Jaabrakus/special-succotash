#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
godot_bin="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
report_dir="${TMPDIR:-/private/tmp}/socom-mobility-regression"
mkdir -p "$report_dir"

"$godot_bin" \
  --headless \
  --log-file "$report_dir/mobility.log" \
  --path "$project_dir" \
  --script res://tools/mobility_regression.gd

if rg -q 'SCRIPT ERROR|Parse Error|MOBILITY_CHECK FAIL|MOBILITY_REGRESSION FAIL' "$report_dir/mobility.log"; then
  print -u2 "FAIL: mobility regression reported an error"
  exit 1
fi

if ! rg -q 'MOBILITY_REGRESSION PASS' "$report_dir/mobility.log"; then
  print -u2 "FAIL: mobility regression did not complete"
  exit 1
fi

print "3D mobility regression: aim-relative strafing, torso/leg handoff, stances, jump, dive, and rolls passed"
print "Mobility regression report: $report_dir/mobility.log"
