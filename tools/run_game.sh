#!/bin/bash
set -e

GODOT_BIN="/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot"
PROJECT_DIR="/Users/kiwimango/socom-141-camera-lab"

echo "=== LAUNCHING SOCOM 141 PLAYABLE ARENA ==="
"$GODOT_BIN" --path "$PROJECT_DIR" "res://main.tscn" "$@"
