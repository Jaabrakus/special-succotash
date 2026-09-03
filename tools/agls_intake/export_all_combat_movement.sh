#!/bin/zsh
set -euo pipefail

SOCOM_PROJECT="/Users/kiwimango/Documents/SOCOM-141"
AGLS_PROJECT="/Users/kiwimango/AGLS v1.9.2 UE5.7"
MANIFEST="$SOCOM_PROJECT/config/agls_traversal_asset_manifest.json"
FAMILIES=(
  weapon_hold weapon_reload weapon_recoil weapon_equip weapon_pickup
  locomotion_idle locomotion_walk locomotion_run locomotion_turn
  locomotion_crouch locomotion_crawl locomotion_air locomotion_roll
  locomotion_additive grenade
)

python3 "$SOCOM_PROJECT/tools/agls_intake/build_manifest.py" \
  --source-project "$AGLS_PROJECT" \
  --output "$MANIFEST"

for family in $FAMILIES; do
  candidates=$(python3 - "$MANIFEST" "$family" <<'PY'
import json
import sys
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
print(int(manifest["families"][sys.argv[2]]["exportable_count"]))
PY
)
  batches=$(( (candidates + 63) / 64 ))
  echo "Exporting $family in $batches bounded pass(es)"
  for (( batch = 1; batch <= batches; batch++ )); do
    "$SOCOM_PROJECT/tools/agls_intake/run_export_batch.sh" "$family" 64
  done
done

echo "All cataloged combat and ground-movement animation families completed their export passes."
