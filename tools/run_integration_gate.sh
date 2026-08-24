#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
godot_bin="${GODOT_BIN:-/Users/kiwimango/Downloads/Godot.app/Contents/MacOS/Godot}"
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
if rg -q 'SCRIPT ERROR|Parse Error' "$report_dir/project-parse.log"; then
  print -u2 "FAIL: project parse reported a script error"
  exit 1
fi

run_godot_check() {
  local label="$1"
  local script_path="$2"
  local pass_marker="$3"
  local log_path="$report_dir/${label}.log"
  print "Running $label"
  "$godot_bin" \
    --headless \
    --rendering-method gl_compatibility \
    --log-file "$log_path" \
    --path "$project_dir" \
    --script "$script_path"
  if rg -q 'SCRIPT ERROR|Parse Error|_CHECK FAIL|_REGRESSION FAIL' "$log_path"; then
    print -u2 "FAIL: $label reported an error"
    exit 1
  fi
  if ! rg -q "$pass_marker" "$log_path"; then
    print -u2 "FAIL: $label did not print its pass marker"
    exit 1
  fi
}

run_godot_check "manifest" "res://tools/integration_manifest_regression.gd" "INTEGRATION_MANIFEST_REGRESSION PASS"
run_godot_check "playtest-state-collection" "res://tools/playtest_state_collection_regression.gd" "PLAYTEST_STATE_COLLECTION_REGRESSION PASS"
run_godot_check "studio-navigation" "res://tools/studio_navigation_regression.gd" "STUDIO_NAVIGATION_REGRESSION PASS"
run_godot_check "animation-studio-architecture" "res://tools/animation_studio_architecture_regression.gd" "ANIMATION_STUDIO_ARCHITECTURE_REGRESSION PASS"
run_godot_check "animation-workshop-repository" "res://tools/animation_workshop_repository_regression.gd" "ANIMATION_WORKSHOP_REPOSITORY_REGRESSION PASS"
run_godot_check "animation-sequence-service" "res://tools/animation_sequence_service_regression.gd" "ANIMATION_SEQUENCE_SERVICE_REGRESSION PASS"
run_godot_check "apple-mocap-pipeline" "res://tools/apple_mocap_pipeline_regression.gd" "APPLE_MOCAP_PIPELINE_REGRESSION PASS"
run_godot_check "pose-ownership-contract" "res://tools/pose_ownership_contract_regression.gd" "POSE_OWNERSHIP_CONTRACT_REGRESSION PASS"
"$project_dir/tools/run_operator_config_validation.sh"
"$project_dir/tools/run_operator_animation_regression.sh"
"$project_dir/tools/run_operator_weapon_pose_regression.sh"
"$project_dir/tools/run_mobility_regression.sh"
run_godot_check "gun-lab" "res://tools/gun_lab_animation_catalog_regression.gd" "GUN_LAB_ANIMATION_CATALOG_REGRESSION PASS"
run_godot_check "weapon-rig-integration" "res://tools/weapon_rig_integration_regression.gd" "WEAPON_RIG_INTEGRATION_REGRESSION PASS"
run_godot_check "weapon-equipment-event" "res://tools/weapon_equipment_event_regression.gd" "WEAPON_EQUIPMENT_EVENT_REGRESSION PASS"
run_godot_check "player-ammunition-ownership" "res://tools/player_health_weapon_ammo_regression.gd" "PLAYER_HEALTH_WEAPON_AMMO_REGRESSION PASS"
run_godot_check "dynamic-hand-ownership" "res://tools/test_dynamic_hand_owned_weapon.gd" "DYNAMIC_HAND_OWNERSHIP_REGRESSION PASS"
run_godot_check "dynamic-reload-handoff" "res://tools/test_dynamic_reload_handoff.gd" "DYNAMIC_RELOAD_HANDOFF_REGRESSION PASS"
run_godot_check "prone-grounding" "res://tools/prone_grounding_regression.gd" "PRONE_GROUNDING_REGRESSION PASS"

if [[ "$mode" == "full" ]]; then
	run_godot_check "commercial-asset-register" "res://tools/commercial_asset_clearance_audit.gd" "COMMERCIAL_ASSET_AUDIT PASS"
	"$project_dir/tools/release_protection_check.sh"
	"$project_dir/tools/run_startup_performance_regression.sh"
	"$project_dir/tools/run_operator_locomotion_quality_regression.sh"
  "$project_dir/tools/run_operator_pose_tool_regression.sh"
  "$project_dir/tools/run_input_device_ownership_regression.sh"
  "$project_dir/tools/run_reticle_render_integration.sh"
  "$project_dir/tools/run_camera_regression.sh"
fi

print "SOCOM-141 $mode integration gate PASS"
print "Reports: $report_dir"
