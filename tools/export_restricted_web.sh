#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

godot_bin=${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}
output_dir="$project_root/builds/web"
export_log=/private/tmp/141-restricted-web-export.log

if [ ! -x "$godot_bin" ]; then
	printf 'Godot executable not found: %s\n' "$godot_bin" >&2
	exit 1
fi

tools/release_protection_check.sh
mkdir -p "$output_dir"

"$godot_bin" --headless --log-file /private/tmp/141-public-launcher-regression.log \
	--path "$project_root" --script res://tools/restricted_web_launcher_regression.gd \
	-- --restricted-web-preview

"$godot_bin" --headless --log-file /private/tmp/141-public-training-regression.log \
	--path "$project_root" --script res://tools/public_training_range_regression.gd \
	-- --restricted-web-preview

"$godot_bin" --headless --log-file "$export_log" \
	--path "$project_root" --export-release \
	"141 Restricted Web" "$output_dir/index.html"

if rg -q 'Storing File: res://(tools/|art_source/|reference/|assets/(animation_reference|art_direction)/|builds/|animation_library_lab\.tscn|apple_mocap_intake_lab\.tscn|composure_reticle_lab\.tscn|gun_calibration_lab\.tscn|keyboard_mapping_lab\.tscn|sound_engine_lab\.tscn|studio_hub\.tscn|tactical_grenade_lab\.tscn)' "$export_log"; then
	printf 'Restricted Web export contains a forbidden development path. See %s\n' "$export_log" >&2
	exit 1
fi

if rg 'Storing File: res://scripts/labs/' "$export_log" | rg -vq 'res://scripts/labs/map_creation_lab\.gd'; then
	printf 'Restricted Web export contains a non-player lab controller. See %s\n' "$export_log" >&2
	exit 1
fi

cp web/robots.txt "$output_dir/robots.txt"
cp web/ai.txt "$output_dir/ai.txt"
cp LICENSE.md "$output_dir/LICENSE.md"
cp AI_TRAINING_POLICY.md "$output_dir/AI_TRAINING_POLICY.md"
cp THIRD_PARTY_NOTICES.md "$output_dir/THIRD_PARTY_NOTICES.md"

build_id=$(git rev-parse --short=12 HEAD)
if ! git diff --quiet --ignore-submodules --; then
	build_id="${build_id}-dirty"
fi
printf '141 restricted web build %s\n' "$build_id" > "$output_dir/BUILD_ID.txt"

(
	cd "$output_dir"
	shasum -a 256 index.html ./*.js ./*.wasm ./*.pck BUILD_ID.txt 2>/dev/null \
		> SHA256SUMS.txt
	shasum -a 256 -c SHA256SUMS.txt
)

printf 'Restricted Web build ready: %s\n' "$output_dir"
