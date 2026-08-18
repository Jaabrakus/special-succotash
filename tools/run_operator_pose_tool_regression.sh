#!/bin/zsh
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
REPORT_DIR="${TMPDIR:-/private/tmp}/socom-operator-pose-tool"
mkdir -p "$REPORT_DIR"

"$GODOT_BIN" \
  --headless \
  --log-file "$REPORT_DIR/pose-tool.log" \
  --path "$PROJECT_DIR" \
  --script res://tools/operator_pose_tool_regression.gd

echo "Pose tool report: $REPORT_DIR/pose-tool.log"
