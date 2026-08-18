#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
godot_bin="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
current_branch="$(git -C "$project_dir" branch --show-current)"

if [[ "$current_branch" != "main" ]]; then
  print -u2 "Refusing to launch a noncanonical gameplay build: $current_branch"
  print -u2 "Open /Users/kiwimango/Documents/SOCOM-141 instead."
  exit 1
fi

print "SOCOM-141 CANONICAL PLAYABLE ARENA"
print "Project: $project_dir"
print "Build:   main@$(git -C "$project_dir" rev-parse --short HEAD)"
exec "$godot_bin" --path "$project_dir" res://main.tscn "$@"
