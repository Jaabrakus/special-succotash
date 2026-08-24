extends SceneTree

const WeaponRigContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const HurtboxProfile := preload("res://scripts/combat/socom_hurtbox_profile.gd")
const ProceduralPoseProfile := preload("res://scripts/player/operator_procedural_pose_profile.gd")
const AnimationProfile := preload("res://scripts/player/operator_animation_profile.gd")
const AnimationAudioProfile := preload("res://scripts/audio/audio_animation_event_profile.gd")
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")

const REQUIRED_STATES := [
	"operator_loadout",
	"equipped_weapon",
	"animation_map",
	"animation_layers",
	"procedural_pose",
	"movement",
	"hurtboxes",
	"animation_audio",
	"surface_audio",
	"map",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var collector := root.get_node_or_null("PlaytestStateCollector")
	_expect(collector != null, "playtest collector autoload exists")
	if collector == null:
		_finish()
		return
	var selected_map := MapDocument.load_path("res://config/maps/current_map.json")
	selected_map["map_id"] = "map_playtest_selected_regression"
	selected_map["name"] = "Selected Map Regression"
	ProjectSettings.set_setting(
		"socom/session/selected_map_document",
		selected_map.duplicate(true)
	)
	var result: Dictionary = collector.call("collect_saved_state")
	_expect(bool(result.get("ok", false)), "all saved lab profiles validate")
	var bundle: Dictionary = result.get("bundle", {})
	var states: Dictionary = bundle.get("states", {})
	var sources: Dictionary = bundle.get("sources", {})
	for state_id in REQUIRED_STATES:
		_expect(states.has(state_id), "bundle includes %s" % state_id)
		_expect(sources.has(state_id), "bundle records source for %s" % state_id)
		if sources.has(state_id):
			_expect(
				not String((sources[state_id] as Dictionary).get("sha256", "")).is_empty(),
				"bundle fingerprints %s" % state_id
			)
	_expect(
		not String(bundle.get("equipped_weapon_id", "")).is_empty(),
		"bundle identifies the equipped weapon"
	)
	_expect(
		String((states.get("map", {}) as Dictionary).get("map_id", ""))
		== "map_playtest_selected_regression",
		"bundle preserves the map selected in the editor"
	)
	_expect(
		String((sources.get("map", {}) as Dictionary).get("path", ""))
		== "session://selected_map_document",
		"bundle records the selected-map handoff instead of the bundled fallback"
	)
	_expect(
		ProjectSettings.get_setting("socom/playtest/active_bundle", {}) is Dictionary,
		"bundle is published for the next gameplay scene"
	)

	# Runtime readers must consume this one snapshot, not independently reopen
	# files after the Play button has collected them.
	var sentinel_bundle := bundle.duplicate(true)
	var sentinel_states: Dictionary = sentinel_bundle["states"]
	(sentinel_states["equipped_weapon"] as Dictionary)["weapon_id"] = "bundle_snapshot_test"
	var hurtbox_state: Dictionary = sentinel_states["hurtboxes"]
	(hurtbox_state["radius_scales"] as Dictionary)["global"] = 0.51
	var pose_state: Dictionary = sentinel_states["procedural_pose"]
	(((pose_state["postures"] as Dictionary)["STANDING"] as Dictionary)["head"] as Dictionary)["yaw"] = 7.0
	var animation_state: Dictionary = sentinel_states["animation_map"]
	(animation_state["locomotion"] as Dictionary)["walk_nominal_speed_mps"] = 2.37
	var audio_state: Dictionary = sentinel_states["animation_audio"]
	(audio_state["animations"] as Dictionary)["bundle_snapshot_test"] = [{"time": 0.0, "cue": "bundle_cue"}]
	ProjectSettings.set_setting("socom/playtest/active_bundle", sentinel_bundle)
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", true)
	_expect(
		String(WeaponRigContract.load_equipped_config().get("weapon_id", "")) == "bundle_snapshot_test",
		"weapon runtime consumes the collected snapshot"
	)
	_expect(
		is_equal_approx(float(HurtboxProfile.load_scales().get("global", 0.0)), 0.51),
		"hurtbox runtime consumes the collected snapshot"
	)
	var pose_profile := ProceduralPoseProfile.new()
	pose_profile.load_project_profile()
	_expect(
		is_equal_approx(pose_profile.get_rotation_degrees(&"STANDING", &"head").y, 7.0),
		"procedural pose runtime consumes the collected snapshot"
	)
	var animation_profile := AnimationProfile.new()
	animation_profile.load_project_map()
	_expect(
		is_equal_approx(float(animation_profile.locomotion.get("walk_nominal_speed_mps", 0.0)), 2.37),
		"animation runtime consumes the collected snapshot"
	)
	var audio_profile := AnimationAudioProfile.new()
	audio_profile.load_from_file()
	_expect(
		not audio_profile.events_for(&"bundle_snapshot_test").is_empty(),
		"audio runtime consumes the collected snapshot"
	)
	ProjectSettings.set_setting("socom/playtest/active_bundle", bundle)

	change_scene_to_file("res://game_launcher.tscn")
	for _frame in 3:
		await process_frame
	var launcher := current_scene
	_expect(launcher != null, "play launcher opens")
	if launcher:
		launcher.call("_collect_and_open", "res://main.tscn")
		for _frame in 12:
			await process_frame
		_expect(
			current_scene != null and current_scene.scene_file_path == "res://main.tscn",
			"Play collects saved state before opening main"
		)
		_expect(
			current_scene != null and current_scene.has_meta("playtest_state_bundle"),
			"main receives the collected saved-state bundle"
		)
	_finish()


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("PLAYTEST_STATE_COLLECTION_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("PLAYTEST_STATE_COLLECTION_REGRESSION: %s" % failure)
	quit(1)
