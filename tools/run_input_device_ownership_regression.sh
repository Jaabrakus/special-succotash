#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
godot_bin="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
report="${TMPDIR:-/private/tmp}/socom-input-device-ownership-regression.log"

"$godot_bin" --headless --log-file "$report" --path "$project_dir" \
  --script res://tools/input_device_ownership_regression.gd

if grep -Eq 'SCRIPT ERROR|Parse Error|INPUT_DEVICE_OWNERSHIP_REGRESSION FAIL' "$report"; then
  print -u2 "FAIL: input device ownership regression reported an error"
  exit 1
fi
if ! grep -q 'INPUT_DEVICE_OWNERSHIP_REGRESSION PASS' "$report"; then
  print -u2 "FAIL: input device ownership regression did not complete"
  exit 1
fi

print "Input device ownership regression: PASS"
print "Report: $report"
