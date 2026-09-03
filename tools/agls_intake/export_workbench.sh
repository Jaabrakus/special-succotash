#!/bin/zsh
set -euo pipefail

SOCOM_PROJECT="/Users/kiwimango/Documents/SOCOM-141"
AGLS_PROJECT="/Users/kiwimango/AGLS v1.9.2 UE5.7"
UNREAL_COMMAND="/Users/Shared/Epic Games/UE_5.8/Engine/Binaries/Mac/UnrealEditor-Cmd"
OUTPUT_ROOT="$SOCOM_PROJECT/assets/external/agls_intake/raw/interaction_workbench"
MINIMUM_FREE_KB=4194304

AVAILABLE_KB=$(df -k "$SOCOM_PROJECT" | awk 'NR == 2 {print $4}')
if (( AVAILABLE_KB < MINIMUM_FREE_KB )); then
  echo "Refusing export: at least 4 GiB free is required; ${AVAILABLE_KB} KiB is available."
  exit 2
fi

"$UNREAL_COMMAND" "$AGLS_PROJECT/AGLS.uproject" \
  -run=pythonscript \
  -script="$SOCOM_PROJECT/tools/agls_intake/unreal_export_workbench.py" \
  -aglsoutput="$OUTPUT_ROOT" \
  -EnablePlugins=PythonScriptPlugin,EditorScriptingUtilities \
  -unattended -nosplash -nullrhi -NoSound -NoShaderCompile -NoCompile -NoLiveCoding \
  -stdout -FullStdOutLogOutput
