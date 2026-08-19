#!/bin/zsh
set -euo pipefail

tool_dir="${0:A:h}"
output="$tool_dir/apple_mocap_extract"
module_cache="${TMPDIR:-/tmp}/socom-141-swift-module-cache"
mkdir -p "$module_cache"
xcrun swiftc \
  -O \
  -module-cache-path "$module_cache" \
  -framework Foundation \
  -framework AVFoundation \
  -framework Vision \
  -framework ImageIO \
  "$tool_dir/AppleMocapExtractor.swift" \
  -o "$output"
print "$output"
