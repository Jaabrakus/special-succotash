#!/bin/zsh
set -euo pipefail

GODOT_BIN="/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot"
REPORT_PATH="${TMPDIR:-/private/tmp}/socom-operator-root-sanitizer.log"

"$GODOT_BIN" --headless --log-file "$REPORT_PATH" --path . --script res://tools/operator_root_sanitizer_regression.gd
echo "Operator root sanitizer report: $REPORT_PATH"
