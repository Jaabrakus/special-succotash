#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
godot_bin="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
report="${TMPDIR:-/private/tmp}/socom-orbit-trail-regression.log"

"$godot_bin" --headless --log-file "$report" --path "$project_dir" \
  --script res://tools/orbit_trail_regression.gd

if grep -Eq 'SCRIPT ERROR|Parse Error|ORBIT_TRAIL_REGRESSION FAIL' "$report"; then
  print -u2 "FAIL: orbit trail regression reported an error"
  exit 1
fi

if ! grep -q 'ORBIT_TRAIL_REGRESSION PASS' "$report"; then
  print -u2 "FAIL: orbit trail regression did not complete"
  exit 1
fi

print "Orbit trail regression: PASS"
print "Report: $report"
