#!/bin/zsh
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BLENDER_BIN="${BLENDER_BIN:-/Users/kiwimango/Applications/Blender-4.5-LTS.app/Contents/MacOS/Blender}"
MIXAMO_ROOT="${MIXAMO_ROOT:-/Users/kiwimango/Downloads/socom_141_camera_lab/Basic Shooter Pack}"

"$BLENDER_BIN" \
    --background "$PROJECT_DIR/art_source/operator3d/socom_141_operator_animation_source.blend" \
    --python "$PROJECT_DIR/tools/retarget_mixamo_operator.py" -- \
    "$MIXAMO_ROOT" \
    "$PROJECT_DIR/assets/characters/operator3d/socom_141_operator_animated.glb" \
    "$PROJECT_DIR/assets/characters/operator3d/operator_animation_library.json"

echo "Curated Mixamo animations baked into the 65-bone SOCOM operator"
