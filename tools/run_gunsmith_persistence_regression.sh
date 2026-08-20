#!/usr/bin/env bash
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
if [[ ! -x "$GODOT_BIN" ]]; then
  GODOT_BIN="$(command -v godot || true)"
fi

if [[ -z "$GODOT_BIN" || ! -x "$GODOT_BIN" ]]; then
  echo "Error: Godot binary not found." >&2
  exit 1
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Running Gunsmith Persistence & Rig Regression Tests..."
"$GODOT_BIN" --headless --path "$PROJECT_DIR" -s res://tools/test_gunsmith_persistence_regression.gd

