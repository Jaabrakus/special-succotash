#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
godot_bin="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
canonical_branch="main"
current_branch="$(git -C "$project_dir" branch --show-current)"
current_commit="$(git -C "$project_dir" rev-parse --short HEAD)"

if [[ "$current_branch" != "$canonical_branch" ]]; then
  print -u2 "Refusing to open a parallel timeline: $current_branch"
  print -u2 "Open /Users/kiwimango/Documents/SOCOM-141 instead."
  exit 1
fi

print "SOCOM-141 CANONICAL STUDIO"
print "Project: $project_dir"
print "Build:   $canonical_branch@$current_commit"
exec "$godot_bin" --path "$project_dir" res://studio_hub.tscn -- --studio
