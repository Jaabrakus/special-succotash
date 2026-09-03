#!/bin/zsh
set -euo pipefail

SOCOM_PROJECT="/Users/kiwimango/Documents/SOCOM-141"
SOURCE_PATH="${1:-}"
DESTINATION_PATH="${2:-}"
GODOT_COMMAND="${GODOT_COMMAND:-}"

if [[ -z "$SOURCE_PATH" || -z "$DESTINATION_PATH" ]]; then
  echo "Usage: import_glb_scene.sh <source.glb> <destination.scn>"
  exit 2
fi
if [[ ! -f "$SOURCE_PATH" || "$SOURCE_PATH" != *.glb ]]; then
  echo "GLB source does not exist: $SOURCE_PATH"
  exit 2
fi
if [[ "$DESTINATION_PATH" != "$SOCOM_PROJECT"/* || "$DESTINATION_PATH" != *.scn ]]; then
  echo "Destination must be a .scn below the canonical SOCOM project."
  exit 2
fi

if [[ -z "$GODOT_COMMAND" ]]; then
  for candidate in \
    "/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot" \
    "/Applications/Godot.app/Contents/MacOS/Godot" \
    "/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot"; do
    if [[ -x "$candidate" ]]; then
      GODOT_COMMAND="$candidate"
      break
    fi
  done
fi
if [[ ! -x "$GODOT_COMMAND" ]]; then
  echo "Godot executable was not found. Set GODOT_COMMAND to the installed binary."
  exit 2
fi

PROBE_DIRECTORY=$(mktemp -d /tmp/socom-agls-glb-import.XXXXXX)
cleanup_probe() {
  if [[ "$PROBE_DIRECTORY" == /tmp/socom-agls-glb-import.* ]]; then
    rm -rf "$PROBE_DIRECTORY"
  fi
}
trap cleanup_probe EXIT

SOURCE_NAME="${SOURCE_PATH:t}"
cp "$SOCOM_PROJECT/tools/agls_intake/godot_probe_project.godot" "$PROBE_DIRECTORY/project.godot"
ln "$SOURCE_PATH" "$PROBE_DIRECTORY/$SOURCE_NAME"
"$GODOT_COMMAND" --headless --editor --path "$PROBE_DIRECTORY" --import

IMPORT_FILE="$PROBE_DIRECTORY/$SOURCE_NAME.import"
CACHE_RESOURCE=$(awk -F'"' '/^path="res:\/\/.godot\/imported\// {print $2; exit}' "$IMPORT_FILE")
CACHE_FILE="$PROBE_DIRECTORY/${CACHE_RESOURCE#res://}"
if [[ ! -f "$CACHE_FILE" ]]; then
  echo "Godot did not produce an imported scene for $SOURCE_NAME"
  exit 3
fi
mkdir -p "${DESTINATION_PATH:h}"
cp "$CACHE_FILE" "$DESTINATION_PATH"
echo "Published imported GLB scene -> $DESTINATION_PATH"
