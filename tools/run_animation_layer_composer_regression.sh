#!/bin/zsh
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
REPORT_PATH="${TMPDIR:-/tmp}/socom-animation-layer-composer.log"
"$GODOT_BIN" --headless --log-file "$REPORT_PATH" --path "$PROJECT_DIR" --script res://tools/animation_layer_composer_regression.gd
