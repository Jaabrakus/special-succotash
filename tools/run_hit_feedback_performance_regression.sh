#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
godot_bin="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
report="${TMPDIR:-/private/tmp}/socom-hit-feedback-performance.log"

"$godot_bin" --headless --log-file "$report" --path "$project_dir" \
  --script res://tools/hit_feedback_performance_regression.gd

if grep -Eq 'SCRIPT ERROR|Parse Error|HIT_FEEDBACK_PERFORMANCE_REGRESSION FAIL' "$report"; then
  print -u2 "FAIL: hit feedback performance regression reported an error"
  exit 1
fi
if ! grep -q 'HIT_FEEDBACK_PERFORMANCE_REGRESSION PASS' "$report"; then
  print -u2 "FAIL: hit feedback performance regression did not complete"
  exit 1
fi

print "Hit feedback performance regression: PASS"
print "Report: $report"
