#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
godot_bin="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
report_path="${TMPDIR:-/private/tmp}/socom-prone-locomotion-regression.log"

"$godot_bin" \
  --headless \
  --log-file "$report_path" \
  --path "$project_dir" \
  --script res://tools/prone_locomotion_probe.gd

if ! rg -q 'PRONE_LOCOMOTION_REGRESSION PASS' "$report_path"; then
  print -u2 "FAIL: prone locomotion regression did not pass"
  exit 1
fi

print "Prone body alignment and crawl continuity passed"
print "Prone report: $report_path"
