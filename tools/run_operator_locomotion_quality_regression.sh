#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
godot_bin="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
report_path="${TMPDIR:-/private/tmp}/socom-operator-locomotion-quality.log"

"$godot_bin" \
  --headless \
  --log-file "$report_path" \
  --path "$project_dir" \
  --script res://tools/operator_locomotion_quality_regression.gd

if ! rg -q 'OPERATOR_LOCOMOTION_QUALITY_REGRESSION PASS' "$report_path"; then
  print -u2 "FAIL: operator locomotion quality regression did not pass"
  exit 1
fi

print "Operator locomotion quality metrics passed"
print "Quality report: $report_path"
