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

"$BLENDER_BIN" \
    --background \
    --python "$PROJECT_DIR/tools/export_mixamo_skin.py" -- \
    "$MIXAMO_ROOT/Rifle Aiming Idle.fbx" \
    "$PROJECT_DIR/assets/characters/operator3d/mixamo_beta_skin.glb"

echo "Curated Mixamo animations baked and visible Beta skin exported for the 65-bone SOCOM operator"
