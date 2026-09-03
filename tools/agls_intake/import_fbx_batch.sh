#!/bin/zsh
set -euo pipefail

SOCOM_PROJECT="/Users/kiwimango/Documents/SOCOM-141"
GODOT_COMMAND="${GODOT_COMMAND:-}"
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
RAW_ROOT="$SOCOM_PROJECT/assets/external/agls_intake/raw"
IMPORTED_ROOT="$SOCOM_PROJECT/assets/external/agls_intake/imported"
FAMILY="${1:-swimming}"
SOURCE_DIRECTORY="$RAW_ROOT/$FAMILY"
DESTINATION_DIRECTORY="$IMPORTED_ROOT/$FAMILY"
PROBE_DIRECTORY=$(mktemp -d /tmp/socom-agls-import.XXXXXX)

cleanup_probe() {
  if [[ "$PROBE_DIRECTORY" == /tmp/socom-agls-import.* ]]; then
    rm -rf "$PROBE_DIRECTORY"
  fi
}
trap cleanup_probe EXIT

if [[ ! -d "$SOURCE_DIRECTORY" ]]; then
  echo "No exported AGLS family directory: $SOURCE_DIRECTORY"
  exit 2
fi

mkdir -p "$DESTINATION_DIRECTORY"
cp "$SOCOM_PROJECT/tools/agls_intake/godot_probe_project.godot" "$PROBE_DIRECTORY/project.godot"
# The disposable project is on the same macOS volume. Hard links prevent the
# large locomotion families from temporarily consuming a second copy of every
# FBX while Godot builds its compact import cache.
ln "$SOURCE_DIRECTORY"/*.fbx "$PROBE_DIRECTORY/"

"$GODOT_COMMAND" --headless --editor --path "$PROBE_DIRECTORY" --import

PUBLISHED=0
for import_file in "$PROBE_DIRECTORY"/*.fbx.import; do
  source_name="${import_file:t:r:r}"
  cache_resource=$(awk -F'"' '/^path="res:\/\/.godot\/imported\// {print $2; exit}' "$import_file")
  cache_file="$PROBE_DIRECTORY/${cache_resource#res://}"
  if [[ ! -f "$cache_file" ]]; then
    echo "Missing imported scene for $source_name"
    exit 3
  fi
  cp "$cache_file" "$DESTINATION_DIRECTORY/$source_name.scn"
  (( PUBLISHED += 1 ))
done

echo "Published $PUBLISHED $FAMILY animation scenes -> $DESTINATION_DIRECTORY"
