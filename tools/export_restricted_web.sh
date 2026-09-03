#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

godot_bin=${GODOT_BIN:-}
output_dir="$project_root/builds/web"
export_log=/private/tmp/141-restricted-web-export.log
itch_archive="$project_root/builds/SOCOM-141-browser.zip"

if [ -z "$godot_bin" ]; then
	for candidate in \
		/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
		/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot
	do
		if [ -x "$candidate" ]; then
			godot_bin=$candidate
			break
		fi
	done
fi

if [ -z "$godot_bin" ] && command -v godot4 >/dev/null 2>&1; then
	godot_bin=$(command -v godot4)
fi

if [ -z "$godot_bin" ] && command -v godot >/dev/null 2>&1; then
	godot_bin=$(command -v godot)
fi

if [ -z "$godot_bin" ] || [ ! -x "$godot_bin" ]; then
	printf 'Godot executable not found: %s\n' "$godot_bin" >&2
	exit 1
fi

godot_version=$("$godot_bin" --version)
case "$godot_version" in
	4.7.1*) ;;
	*)
		printf 'Godot 4.7.1 is required; found %s at %s\n' "$godot_version" "$godot_bin" >&2
		exit 1
		;;
esac

tools/release_protection_check.sh
mkdir -p "$output_dir"

"$godot_bin" --headless --log-file /private/tmp/141-public-launcher-regression.log \
	--path "$project_root" --script res://tools/restricted_web_launcher_regression.gd \
	-- --restricted-web-preview

"$godot_bin" --headless --log-file "$export_log" \
	--path "$project_root" --export-release \
	"141 Restricted Web" "$output_dir/index.html"

if rg -q 'Storing File: res://(tools/|art_source/|reference/|assets/(animation_reference|art_direction)/|builds/|animation_library_lab\.tscn|apple_mocap_intake_lab\.tscn|composure_reticle_lab\.tscn|gun_calibration_lab\.tscn|keyboard_mapping_lab\.tscn|sound_engine_lab\.tscn|studio_hub\.tscn|tactical_grenade_lab\.tscn)' "$export_log"; then
	printf 'Restricted Web export contains a forbidden development path. See %s\n' "$export_log" >&2
	exit 1
fi

if rg 'Storing File: res://scripts/labs/' "$export_log" | rg -vq 'res://scripts/labs/(map_creation_lab|gunsmith2/weapon_visual_rig_(contract|resolver))\.gd'; then
	printf 'Restricted Web export contains a non-player lab controller. See %s\n' "$export_log" >&2
	exit 1
fi

for required_export in \
	'game_launcher.scn' \
	'multiplayer_slice.scn' \
	'res://config/supabase_public.json' \
	'res://config/network/browser_multiarena_deployment.json' \
	'res://config/maps/painterly_coastal_village_2v2.json' \
	'res://scripts/network/socom_matchmaking_directory_client.gdc' \
	'res://scripts/network/socom_multiplayer_lobby_pairing.gdc' \
	'res://scripts/network/socom_multiplayer_session.gdc' \
	'res://scripts/maps/socom_map_runtime.gdc'
do
	if ! rg -Fq "$required_export" "$export_log"; then
		printf 'Restricted Web export is missing %s. See %s\n' "$required_export" "$export_log" >&2
		exit 1
	fi
done

cp web/robots.txt "$output_dir/robots.txt"
cp web/ai.txt "$output_dir/ai.txt"
cp LICENSE.md "$output_dir/LICENSE.md"
cp AI_TRAINING_POLICY.md "$output_dir/AI_TRAINING_POLICY.md"
cp THIRD_PARTY_NOTICES.md "$output_dir/THIRD_PARTY_NOTICES.md"

pck_bytes=$(wc -c < "$output_dir/index.pck" | tr -d ' ')
if [ "$pck_bytes" -gt 200000000 ]; then
	printf 'Restricted Web index.pck exceeds itch.io 200 MB limit: %s bytes\n' "$pck_bytes" >&2
	exit 1
fi

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

total_bytes=$(find "$output_dir" -maxdepth 1 -type f -exec wc -c {} \; | awk '{ total += $1 } END { print total + 0 }')
if [ "$total_bytes" -gt 500000000 ]; then
	printf 'Restricted Web output exceeds itch.io 500 MB extracted limit: %s bytes\n' "$total_bytes" >&2
	exit 1
fi

(
	cd "$output_dir"
	zip -FSq "$itch_archive" \
		index.html index.js index.wasm index.pck \
		index.audio.position.worklet.js index.audio.worklet.js \
		index.apple-touch-icon.png index.icon.png index.png \
		robots.txt ai.txt LICENSE.md AI_TRAINING_POLICY.md THIRD_PARTY_NOTICES.md \
		BUILD_ID.txt SHA256SUMS.txt
)

printf 'Restricted Web build ready: %s (%s bytes extracted)\n' "$output_dir" "$total_bytes"
printf 'itch.io upload archive ready: %s\n' "$itch_archive"
