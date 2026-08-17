#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
godot_bin="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
report="${TMPDIR:-/private/tmp}/socom-mouse-cage-regression.log"

"$godot_bin" --headless --log-file "$report" --path "$project_dir" \
  --script res://tools/mouse_cursor_cage_regression.gd

if grep -Eq 'SCRIPT ERROR|Parse Error|MOUSE_CAGE_REGRESSION FAIL' "$report"; then
  print -u2 "FAIL: mouse cursor cage regression reported an error"
  exit 1
fi
if ! grep -q 'MOUSE_CAGE_REGRESSION PASS' "$report"; then
  print -u2 "FAIL: mouse cursor cage regression did not complete"
  exit 1
fi

print "Mouse cursor cage regression: PASS"
print "Report: $report"
