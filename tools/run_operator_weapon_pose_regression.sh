#!/bin/zsh
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
REPORT_DIR="${TMPDIR:-/tmp}/socom-operator-weapon-pose-regression"
REPORT_PATH="$REPORT_DIR/operator-weapon-pose.log"
mkdir -p "$REPORT_DIR"

"$GODOT_BIN" \
    --headless \
    --rendering-method gl_compatibility \
    --log-file "$REPORT_PATH" \
    --path "$PROJECT_DIR" \
    --script res://tools/operator_weapon_pose_regression.gd

if ! grep -q "OPERATOR_WEAPON_POSE_REGRESSION PASS" "$REPORT_PATH"; then
    echo "FAIL: operator weapon-pose regression did not complete successfully" >&2
    exit 1
fi

echo "Operator weapon pose: shared reticle, human joint limits, stance coverage, and multiplayer authority boundary passed"
echo "Operator weapon-pose report: $REPORT_PATH"
