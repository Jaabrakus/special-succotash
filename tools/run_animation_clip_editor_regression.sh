#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
godot_bin="/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot"
report_dir="${TMPDIR:-/tmp}/socom-animation-clip-editor"
mkdir -p "$report_dir"

"$godot_bin" \
  --headless \
  --path "$project_dir" \
  --log-file "$report_dir/animation-clip-editor.log" \
  --script res://tools/animation_clip_editor_regression.gd

echo "Animation clip editor report: $report_dir/animation-clip-editor.log"
