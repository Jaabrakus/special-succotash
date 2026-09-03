#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
godot_bin="${GODOT_BIN:-/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot}"
export GODOT_BIN="$godot_bin"
mode="${1:-quick}"
report_dir="${TMPDIR:-/private/tmp}/socom-integration-gate"
canonical_branch="main"

if [[ "$mode" != "quick" && "$mode" != "full" ]]; then
  print -u2 "Usage: $0 [quick|full]"
  exit 2
fi

mkdir -p "$report_dir"
current_branch="$(git -C "$project_dir" branch --show-current)"
if [[ "$current_branch" != "$canonical_branch" ]]; then
  print -u2 "FAIL: this is $current_branch; canonical integration is $canonical_branch"
  exit 1
fi

dirty_state="$(git -C "$project_dir" status --porcelain)"
if [[ -n "$dirty_state" ]]; then
  print "NOTICE: integration worktree contains in-progress changes:"
  print "$dirty_state"
  if [[ "${REQUIRE_CLEAN:-0}" == "1" ]]; then
    print -u2 "FAIL: promotion requires a clean integration worktree"
    exit 1
  fi
fi

print "SOCOM-141 $mode integration gate"
print "Project: $project_dir"
print "Branch:  $current_branch"

"$godot_bin" \
  --headless \
  --rendering-method gl_compatibility \
  --log-file "$report_dir/project-parse.log" \
  --path "$project_dir" \
  --editor \
  --quit
if grep -E -q 'SCRIPT ERROR|Parse Error' "$report_dir/project-parse.log"; then
  print -u2 "FAIL: project parse reported a script error"
  exit 1
fi

run_godot_check() {
  local label="$1"
  local script_path="$2"
  local pass_marker="$3"
  local -a script_args=("${@:4}")
  local log_path="$report_dir/${label}.log"
  print "Running $label"
  "$godot_bin" \
    --headless \
    --rendering-method gl_compatibility \
    --log-file "$log_path" \
    --path "$project_dir" \
    --script "$script_path" \
    "${script_args[@]}"
  if grep -E -q 'SCRIPT ERROR|Parse Error|_CHECK FAIL|_REGRESSION FAIL' "$log_path"; then
    print -u2 "FAIL: $label reported an error"
    exit 1
  fi
  if ! grep -E -q "$pass_marker" "$log_path"; then
    print -u2 "FAIL: $label did not print its pass marker"
    exit 1
  fi
}

run_godot_check "manifest" "res://tools/integration_manifest_regression.gd" "INTEGRATION_MANIFEST_REGRESSION PASS"
run_godot_check "playtest-state-collection" "res://tools/playtest_state_collection_regression.gd" "PLAYTEST_STATE_COLLECTION_REGRESSION PASS"
run_godot_check "studio-navigation" "res://tools/studio_navigation_regression.gd" "STUDIO_NAVIGATION_REGRESSION PASS"
run_godot_check "animation-studio-architecture" "res://tools/animation_studio_architecture_regression.gd" "ANIMATION_STUDIO_ARCHITECTURE_REGRESSION PASS"
run_godot_check "editor-animation-authoring" "res://tools/editor_animation_authoring_regression.gd" "EDITOR_ANIMATION_AUTHORING_REGRESSION PASS"
run_godot_check "animation-workshop-repository" "res://tools/animation_workshop_repository_regression.gd" "ANIMATION_WORKSHOP_REPOSITORY_REGRESSION PASS"
run_godot_check "animation-sequence-service" "res://tools/animation_sequence_service_regression.gd" "ANIMATION_SEQUENCE_SERVICE_REGRESSION PASS"
run_godot_check "apple-mocap-pipeline" "res://tools/apple_mocap_pipeline_regression.gd" "APPLE_MOCAP_PIPELINE_REGRESSION PASS"
run_godot_check "pose-ownership-contract" "res://tools/pose_ownership_contract_regression.gd" "POSE_OWNERSHIP_CONTRACT_REGRESSION PASS"
run_godot_check "animation-state-authoring" "res://tools/animation_state_authoring_regression.gd" "ANIMATION_STATE_AUTHORING_REGRESSION PASS"
run_godot_check "operator-pose-pipeline" "res://tools/operator_pose_pipeline_regression.gd" "OPERATOR_POSE_PIPELINE_REGRESSION PASS"
run_godot_check "weapon-auto-reload" "res://tools/weapon_auto_reload_regression.gd" "WEAPON_AUTO_RELOAD_REGRESSION PASS"
run_godot_check "weapon-fire" "res://tools/weapon_fire_regression.gd" "WEAPON_FIRE_REGRESSION PASS" -- --camera-regression-map
run_godot_check "all-weapon-fire-recovery" "res://tools/all_weapon_fire_recovery_regression.gd" "ALL_WEAPON_FIRE_RECOVERY_REGRESSION PASS"
run_godot_check "firearm-family-live-contact" "res://tools/firearm_family_live_contact_regression.gd" "FIREARM_FAMILY_LIVE_CONTACT_REGRESSION PASS"
run_godot_check "gameplay-reload-completion" "res://tools/gameplay_reload_completion_regression.gd" "GAMEPLAY_RELOAD_COMPLETION_REGRESSION PASS"
run_godot_check "feature-contracts" "res://tools/feature_contract_regression.gd" "\[FEATURE CONTRACT\] PASS:"
"$project_dir/tools/run_operator_config_validation.sh"
"$project_dir/tools/run_operator_animation_regression.sh"
"$project_dir/tools/run_operator_weapon_pose_regression.sh"
"$project_dir/tools/run_mobility_regression.sh"
run_godot_check "gun-lab" "res://tools/gun_lab_animation_catalog_regression.gd" "GUN_LAB_ANIMATION_CATALOG_REGRESSION PASS"
run_godot_check "guns-lab-2-profile" "res://tools/guns_lab_2_profile_regression.gd" "GUNS_LAB_2_PROFILE_REGRESSION PASS"
run_godot_check "guns-lab-2-runtime" "res://tools/guns_lab_2_runtime_regression.gd" "GUNS_LAB_2_RUNTIME_REGRESSION PASS"
run_godot_check "firearm-family-presentation" "res://tools/firearm_family_presentation_regression.gd" "FIREARM_FAMILY_PRESENTATION_REGRESSION PASS"
run_godot_check "gunsmith-recom-catalog" "res://tools/gunsmith_recom_catalog_regression.gd" "GUNSMITH_RECOM_CATALOG_REGRESSION PASS"
run_godot_check "buy-menu" "res://tools/buy_menu_regression.gd" "BUY_MENU_REGRESSION PASS"
run_godot_check "weapon-rig-integration" "res://tools/weapon_rig_integration_regression.gd" "WEAPON_RIG_INTEGRATION_REGRESSION PASS"
run_godot_check "weapon-equipment-event" "res://tools/weapon_equipment_event_regression.gd" "WEAPON_EQUIPMENT_EVENT_REGRESSION PASS"
run_godot_check "player-ammunition-ownership" "res://tools/player_health_weapon_ammo_regression.gd" "PLAYER_HEALTH_WEAPON_AMMO_REGRESSION PASS"
run_godot_check "muzzle-obstruction-authority" "res://tools/muzzle_obstruction_regression.gd" "MUZZLE_OBSTRUCTION_REGRESSION PASS"
run_godot_check "multiplayer-slice-architecture" "res://tools/multiplayer_slice_architecture_regression.gd" "MULTIPLAYER_SLICE_ARCHITECTURE_REGRESSION PASS"
run_godot_check "player-hosted-private-match" "res://tools/player_hosted_private_match_regression.gd" "PLAYER_HOSTED_PRIVATE_MATCH_REGRESSION PASS"
run_godot_check "browser-webrtc-private-match" "res://tools/browser_webrtc_private_match_regression.gd" "BROWSER_WEBRTC_PRIVATE_MATCH_REGRESSION PASS" -- --restricted-web-preview
print "Running webrtc-signaling"
npm --prefix "$project_dir/deploy/signaling" test
run_godot_check "multiplayer-demolition" "res://tools/multiplayer_slice_regression.gd" "MULTIPLAYER_SLICE_REGRESSION PASS"
run_godot_check "multiplayer-inheritance" "res://tools/multiplayer_inheritance_regression.gd" "MULTIPLAYER_INHERITANCE_REGRESSION PASS"
run_godot_check "browser-multiarena-deployment" "res://tools/browser_multiarena_deployment_regression.gd" "BROWSER_MULTI_ARENA_DEPLOYMENT_REGRESSION PASS"
run_godot_check "tournament-session" "res://tools/tournament_session_regression.gd" "TOURNAMENT_SESSION_REGRESSION PASS"
run_godot_check "tournament-map-pods" "res://tools/tournament_map_pods_regression.gd" "TOURNAMENT_MAP_PODS_REGRESSION PASS"
run_godot_check "tournament-replication-scope" "res://tools/tournament_replication_scope_regression.gd" "TOURNAMENT_REPLICATION_SCOPE_REGRESSION PASS"
run_godot_check "stair-playability" "res://tools/stair_playability_regression.gd" "STAIR_PLAYABILITY_REGRESSION PASS"
run_godot_check "dynamic-hand-ownership" "res://tools/test_dynamic_hand_owned_weapon.gd" "DYNAMIC_HAND_OWNERSHIP_REGRESSION PASS"
run_godot_check "dynamic-reload-handoff" "res://tools/test_dynamic_reload_handoff.gd" "DYNAMIC_RELOAD_HANDOFF_REGRESSION PASS"
run_godot_check "weapon-presentation-owner" "res://tools/weapon_presentation_owner_regression.gd" "WEAPON_PRESENTATION_OWNER_REGRESSION PASS"
run_godot_check "camera-passage-perception" "res://tools/camera_passage_perception_regression.gd" "CAMERA_PASSAGE_PERCEPTION_REGRESSION PASS"
run_godot_check "prone-grounding" "res://tools/prone_grounding_regression.gd" "PRONE_GROUNDING_REGRESSION PASS"

if [[ "$mode" == "full" ]]; then
	run_godot_check "commercial-asset-register" "res://tools/commercial_asset_clearance_audit.gd" "COMMERCIAL_ASSET_AUDIT PASS"
	"$project_dir/tools/release_protection_check.sh"
	"$project_dir/tools/run_startup_performance_regression.sh"
	"$project_dir/tools/run_multiplayer_lifecycle_probe.sh"
	"$project_dir/tools/run_tournament_websocket_32_peer_probe.sh"
	"$project_dir/tools/run_operator_locomotion_quality_regression.sh"
  "$project_dir/tools/run_operator_pose_tool_regression.sh"
  "$project_dir/tools/run_input_device_ownership_regression.sh"
  "$project_dir/tools/run_reticle_render_integration.sh"
  "$project_dir/tools/run_camera_regression.sh"
fi

print "SOCOM-141 $mode integration gate PASS"
print "Reports: $report_dir"
