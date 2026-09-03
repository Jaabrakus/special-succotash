#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
godot_bin="${GODOT_BIN:-/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot}"
log_path="${TMPDIR:-/private/tmp}/socom-operator-config-validation.log"

"$godot_bin" \
  --headless \
  --log-file "$log_path" \
  --path "$project_dir" \
  --script res://tools/validate_operator_configs.gd

if ! grep -q 'OPERATOR_CONFIG_VALIDATION PASS' "$log_path"; then
  print -u2 "FAIL: operator configuration validation did not pass"
  exit 1
fi

print "Operator tuning and animation maps are valid"
print "Validation report: $log_path"
