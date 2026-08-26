#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
godot_bin="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
canonical_branch="main"
current_branch="$(git -C "$project_dir" branch --show-current)"
current_commit="$(git -C "$project_dir" rev-parse --short HEAD)"
apple_mocap_builder="$project_dir/tools/apple_mocap/build_extractor.sh"
apple_mocap_source="$project_dir/tools/apple_mocap/AppleMocapExtractor.swift"
apple_mocap_binary="$project_dir/tools/apple_mocap/apple_mocap_extract"

if [[ "$current_branch" != "$canonical_branch" ]]; then
  print -u2 "Refusing to open a parallel timeline: $current_branch"
  print -u2 "Open /Users/kiwimango/Documents/SOCOM-141 instead."
  exit 1
fi

print "SOCOM-141 CANONICAL LAUNCHER"
print "Project: $project_dir"
print "Build:   $canonical_branch@$current_commit"
if [[ ! -x "$apple_mocap_binary" || "$apple_mocap_source" -nt "$apple_mocap_binary" ]]; then
  print "Preparing Apple Video Mocap…"
  "$apple_mocap_builder" >/dev/null
fi
exec "$godot_bin" --path "$project_dir" res://game_launcher.tscn -- --studio
