#!/bin/zsh
set -uo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
godot_bin="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
log_path="$(mktemp /tmp/socom-buy-menu-regression.XXXXXX)"

"$godot_bin" \
  --headless \
  --rendering-method gl_compatibility \
  --log-file "$log_path" \
  --path "$project_dir" \
  --script res://tools/buy_menu_regression.gd

exit_code=$?
if [[ $exit_code -ne 0 ]] || grep -qE 'SCRIPT ERROR|_CHECK FAIL|_REGRESSION FAIL' "$log_path"; then
  print -u2 "Buy menu regression failed. Log: $log_path"
  grep -E 'SCRIPT ERROR|_CHECK FAIL|_REGRESSION FAIL' "$log_path"
  exit 1
fi
grep -q 'BUY_MENU_REGRESSION PASS' "$log_path" || { print -u2 "Missing pass marker. Log: $log_path"; exit 1; }
print "Buy menu regression passed."
exit 0
