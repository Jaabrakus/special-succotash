#!/bin/zsh
set -euo pipefail

SOCOM_PROJECT="/Users/kiwimango/Documents/SOCOM-141"

# Keep each Unreal process bounded. Climbing is intentionally split because it
# is much larger than every other traversal family.
for family in ladder rope zipline narrow_ledge wheel_valve mantle_vault; do
  "$SOCOM_PROJECT/tools/agls_intake/run_export_batch.sh" "$family" 64
done

for _batch in 1 2 3 4; do
  "$SOCOM_PROJECT/tools/agls_intake/run_export_batch.sh" climbing 64
done

echo "All cataloged traversal animation families have completed their export passes."
