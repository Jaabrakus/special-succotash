#!/bin/zsh
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
REPORT_DIR="${TMPDIR:-/tmp}/socom-operator-animation-regression"
REPORT_PATH="$REPORT_DIR/operator-animation.log"
mkdir -p "$REPORT_DIR"

"$GODOT_BIN" \
    --headless \
    --log-file "$REPORT_PATH" \
    --path "$PROJECT_DIR" \
    --script res://tools/operator_animation_regression.gd

if ! grep -q "OPERATOR_ANIMATION_REGRESSION PASS" "$REPORT_PATH"; then
    echo "FAIL: operator animation regression did not complete successfully" >&2
    exit 1
fi

echo "Operator animation regression: 122 clips, low-ready selection, combat-ready transitions, obstruction poses, recovery, actions, and gestures passed"
echo "Operator animation report: $REPORT_PATH"
