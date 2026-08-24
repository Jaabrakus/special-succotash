#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
godot_bin="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
report_dir="${TMPDIR:-/private/tmp}/socom-startup-performance-regression"
mkdir -p "$report_dir"

"$godot_bin" \
  --headless \
  --rendering-method gl_compatibility \
  --log-file "$report_dir/startup-performance.log" \
  --path "$project_dir" \
  --script res://tools/startup_performance_regression.gd \
  -- --test-playable-warmup

if rg -q 'SCRIPT ERROR|Parse Error|STARTUP_PERFORMANCE_REGRESSION:' "$report_dir/startup-performance.log"; then
  print -u2 "FAIL: startup performance regression reported an error"
  exit 1
fi

if ! rg -q 'STARTUP_PERFORMANCE_REGRESSION PASS' "$report_dir/startup-performance.log"; then
  print -u2 "FAIL: startup performance regression did not complete"
  exit 1
fi

print "Startup performance regression passed"
print "Startup performance report: $report_dir/startup-performance.log"
