#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
godot_bin="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
canonical_branch="movement-animation-integration"
current_branch="$(git -C "$project_dir" branch --show-current)"

if [[ "$current_branch" != "$canonical_branch" ]]; then
  print -u2 "Refusing to open a parallel timeline: $current_branch"
  print -u2 "Open the canonical $canonical_branch worktree instead."
  exit 1
fi

exec "$godot_bin" --path "$project_dir" res://studio_hub.tscn
