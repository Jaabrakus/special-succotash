extends SceneTree

## Temporary hard ceilings stop the remaining god files from crossing their
## next size boundary. Lower each ceiling after a successful extraction.
const TEMPORARY_CEILINGS := {
	"res://scripts/labs/gun_calibration_lab.gd": 6700,
	"res://scripts/labs/map_creation_lab.gd": 2900,
	"res://scripts/labs/animation_studio/animation_studio_pose_input.gd": 500,
	"res://scripts/labs/animation_studio/animation_studio_pose_strip.gd": 500,
	"res://scripts/labs/animation_studio/animation_studio_pose_corrections.gd": 500,
	"res://scripts/labs/animation_studio/animation_studio_pose_authoring.gd": 50,
	"res://scripts/main.gd": 500,
	"res://scripts/runtime/main_animation_studio.gd": 500,
	"res://scripts/runtime/main_camera_debug_tools.gd": 500,
	"res://scripts/runtime/main_frame_runtime.gd": 500,
	"res://scripts/runtime/main_gameplay_hud.gd": 500,
	"res://scripts/runtime/main_grenade_runtime.gd": 500,
	"res://scripts/runtime/main_grenade_trajectory.gd": 500,
	"res://scripts/runtime/main_training_world.gd": 500,
	"res://scripts/runtime/main_weapon_runtime.gd": 500,
	"res://scripts/runtime/operator_tuning_profile.gd": 500,
	"res://scripts/network/socom_multiplayer_state.gd": 500,
	"res://scripts/network/socom_multiplayer_admission.gd": 500,
	"res://scripts/network/socom_multiplayer_session.gd": 500,
	"res://scripts/network/socom_multiplayer_replication.gd": 500,
	"res://scripts/network/socom_multiplayer_combat.gd": 500,
	"res://scripts/network/socom_multiplayer_rounds.gd": 500,
	"res://scripts/network/socom_multiplayer_objectives.gd": 500,
	"res://scripts/network/socom_multiplayer_world_ui.gd": 500,
	"res://scripts/network/socom_multiplayer_slice.gd": 300,
	"res://scripts/player/operator_weapon_pose_state.gd": 500,
	"res://scripts/player/operator_weapon_pose_kinematics.gd": 500,
	"res://scripts/player/operator_weapon_pose_actions.gd": 500,
	"res://scripts/player/operator_weapon_pose_placement.gd": 500,
	"res://scripts/player/operator_weapon_pose_ready.gd": 500,
	"res://scripts/player/operator_weapon_pose_api.gd": 500,
	"res://scripts/player/operator_weapon_pose_solver.gd": 50,
	"res://scripts/maps/socom_map_runtime.gd": 1400,
	"res://scripts/player/operator_animation_driver_state.gd": 500,
	"res://scripts/player/operator_animation_driver_api.gd": 500,
	"res://scripts/player/operator_animation_driver_pose.gd": 500,
	"res://scripts/player/operator_animation_driver_actions.gd": 500,
	"res://scripts/player/operator_animation_driver_presentation.gd": 500,
	"res://scripts/player/operator_animation_driver_diagnostics.gd": 500,
	"res://scripts/player/operator_animation_driver_runtime.gd": 500,
	"res://scripts/player/operator_animation_driver.gd": 50,
}
const NEW_GOD_FILE_LIMIT := 1000

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var script_paths: Array[String] = []
	_collect_scripts("res://scripts", script_paths)
	for path: String in script_paths:
		var line_count := _line_count(path)
		if TEMPORARY_CEILINGS.has(path):
			var ceiling := int(TEMPORARY_CEILINGS[path])
			if line_count > ceiling:
				failures.append("%s grew from its %d-line ceiling to %d" % [path, ceiling, line_count])
		elif line_count > NEW_GOD_FILE_LIMIT:
			failures.append("new unbudgeted god file: %s has %d lines" % [path, line_count])
	for path: String in TEMPORARY_CEILINGS:
		if path not in script_paths:
			failures.append("budget references missing script: %s" % path)
	if failures.is_empty():
		print("GOD_FILE_BUDGET_REGRESSION PASS — %d scripts checked" % script_paths.size())
		quit(0)
	else:
		push_error("GOD_FILE_BUDGET_REGRESSION FAIL %s" % str(failures))
		quit(1)


func _collect_scripts(directory_path: String, output: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry_name := directory.get_next()
	while entry_name != "":
		if directory.current_is_dir() and not entry_name.begins_with("."):
			_collect_scripts("%s/%s" % [directory_path, entry_name], output)
		elif entry_name.ends_with(".gd"):
			output.append("%s/%s" % [directory_path, entry_name])
		entry_name = directory.get_next()
	directory.list_dir_end()


func _line_count(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var contents := file.get_as_text()
	if contents.is_empty():
		return 0
	return contents.count("\n") + (0 if contents.ends_with("\n") else 1)
