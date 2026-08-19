#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
godot_bin="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
report_path="${TMPDIR:-/private/tmp}/socom-strafe-latency-regression.log"

"$godot_bin" \
  --headless \
  --log-file "$report_path" \
  --path "$project_dir" \
  --script res://tools/test_strafe_latency_regression.gd

if ! grep -q 'STRAFE_LATENCY_REGRESSION PASS' "$report_path"; then
  print -u2 "FAIL: strafe latency regression did not pass"
  exit 1
fi

print "SOCOM Strafe & Latency Regression passed successfully"
print "Report: $report_path"
