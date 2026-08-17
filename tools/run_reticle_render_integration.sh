#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
godot_bin="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
report="${TMPDIR:-/private/tmp}/socom-reticle-render-integration.log"

"$godot_bin" --headless --log-file "$report" --path "$project_dir" \
  --script res://tools/reticle_render_integration.gd

if grep -Eq 'SCRIPT ERROR|Parse Error|RETICLE_RENDER_INTEGRATION FAIL' "$report"; then
  print -u2 "FAIL: rendered reticle integration reported an error"
  exit 1
fi
if ! grep -q 'RETICLE_RENDER_INTEGRATION PASS' "$report"; then
  print -u2 "FAIL: rendered reticle integration did not complete"
  exit 1
fi

print "Rendered reticle integration: PASS"
print "Report: $report"
