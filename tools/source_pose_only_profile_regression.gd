extends SceneTree

## Saved-profile -> existing production driver/graph/pose consumers. This is a
## headless routing regression; rendered main.tscn proof remains a separate gate.
const Profile = preload("res://scripts/player/operator_animation_profile.gd")
const Driver = preload("res://scripts/player/operator_animation_driver.gd")
const OperatorScene = preload("res://scenes/player/operator_player.tscn")
const Weapons = preload("res://scripts/weapons/weapon_rig_contract.gd")
const LibraryCache = preload("res://scripts/player/operator_animation_library_cache.gd")
const SOURCE_PRESET := "res://config/animation_presets/seal_source_pose_only.json"
const HYBRID_PRESET := "res://config/animation_presets/seal_pistol_hybrid.json"
var failures: Array[String] = []
var native_route_checks := 0


func _initialize() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	_run.call_deferred()


func _run() -> void:
	if not _install_preset(SOURCE_PRESET):
		_finish(0, [])
		return
	var profile := Profile.new()
	profile.load_project_map()
	_check(bool(profile.locomotion.get("source_pose_only", false)), "saved policy consumed by profile")
	var round_trip: Variant = JSON.parse_string(JSON.stringify(profile.locomotion))
	_check(round_trip is Dictionary and round_trip.get("source_pose_only") == true, "policy retains boolean true through JSON round-trip")
	_check(not bool(profile.locomotion.get("legacy_pistol_upper_body", true)), "source preset disables legacy pistol upper")
	var cache := LibraryCache.new()
	var source_fingerprint: String = cache.fingerprint_for(profile)
	profile.locomotion["source_pose_only"] = false
	_check(cache.fingerprint_for(profile) != source_fingerprint, "source flag alone invalidates processed-library cache")
	profile.locomotion["source_pose_only"] = true
	_check(cache.fingerprint_for(profile) == source_fingerprint, "fingerprint is deterministic after toggle")
	profile.load_project_map(HYBRID_PRESET)
	_check(not profile.locomotion.source_pose_only, "reused profile restores false when old preset omits policy")
	profile.load_project_map(SOURCE_PRESET)
	_check(profile.locomotion.source_pose_only, "reused profile can opt back in")
	# The presentation solver expects its real CharacterBody ancestor. Use the
	# canonical operator scene, but leave movement disabled for this route test.
	var operator := OperatorScene.instantiate()
	root.add_child(operator)
	operator.set_local_input_enabled(false)
	operator.set_physics_process(false)
	var driver = operator.get_node("Mannequin/ProductionAnimation")
	await process_frame
	var pistols := 0
	var family_representatives: Dictionary = {}
	for file in DirAccess.get_files_at("res://config/weapons"):
		if not file.ends_with(".json"):
			continue
		var config: Dictionary = Weapons.load_config("res://config/weapons/" + file)
		var family := String(config.get("handling_profile", {}).get("family", ""))
		if family.is_empty():
			continue
		if not family_representatives.has(family):
			family_representatives[family] = config
		if family != "TWO_HAND_PISTOL":
			continue
		pistols += 1
		_check(driver.notify_weapon_equipped(config), file + " equips")
		await process_frame
		_check_source_consumers(driver, file)
		for slot in ["idle_standing", "idle_standing_moving", "idle_crouched", "idle_prone", "ready_standing", "ready_standing_moving", "ready_crouched", "ready_crouched_moving", "ready_prone"]:
			_check_native(driver, driver._equipped_action_clip(slot, &"aim_idle"), file + " " + slot)
		for prefix in ["walk", "run", "crouch"]:
			for direction in ["forward", "backward", "left", "right"]:
				var slot: String = prefix + "_" + direction
				for firing in [false, true]:
					var clip: StringName = driver.locomotion_graph._weapon_locomotion_clip(slot, &"run_forward", driver.available_clips, firing)
					_check_native(driver, clip, file + " " + slot + (" firing" if firing else " carry"))
	_check(pistols >= 9, "all nine normalized catalog pistols covered")
	for family: String in family_representatives:
		_check(driver.notify_weapon_equipped(family_representatives[family]), family + " representative equips")
		await process_frame
		_check_source_consumers(driver, family)
	_check(family_representatives.has("TWO_HAND_RIFLE"), "rifle policy covered")
	_check(family_representatives.has("TWO_HAND_PISTOL"), "pistol policy covered")
	operator.queue_free()
	await process_frame
	if _install_preset(HYBRID_PRESET):
		# New profile/driver deliberately exercises the default false value for
		# older saved profiles; don't reuse the already-merged true dictionary.
		var historical := Profile.new()
		historical.load_project_map()
		_check(not bool(historical.locomotion.get("source_pose_only", true)), "historical preset defaults to false")
		_check(bool(historical.locomotion.get("legacy_pistol_upper_body", false)), "historical preset retains opt-in upper layer")
		var fallback := Driver.new()
		root.add_child(fallback)
		await process_frame
		_check(fallback.notify_weapon_equipped(Weapons.load_config("res://config/weapons/mark_23.json")), "fallback pistol equips")
		await process_frame
		_check(not fallback.source_pose_only, "fallback driver consumes false")
		_check(not fallback.posture_layer.source_pose_only and not fallback.weapon_pose_solver.source_pose_only, "fallback forwards false to existing consumers")
		_check(fallback.animation_tree.tree_root.has_node(&"legacy_pistol_upper"), "false policy preserves historical layer")
		fallback.queue_free()
		await process_frame
	_finish(pistols, family_representatives.keys())


func _install_preset(path: String) -> bool:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(raw is Dictionary, "preset is valid dictionary " + path)
	if not raw is Dictionary:
		return false
	var collector := root.get_node("PlaytestStateCollector")
	var result: Dictionary = collector.call("collect_saved_state")
	_check(bool(result.get("ok", false)), "saved state collection")
	if not bool(result.get("ok", false)):
		return false
	var bundle: Dictionary = result.bundle.duplicate(true)
	bundle.states.animation_map = raw.duplicate(true)
	collector.set("active_bundle", bundle)
	ProjectSettings.set_setting("socom/playtest/active_bundle", bundle)
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", true)
	return true


func _check_source_consumers(driver, label: String) -> void:
	_check(driver.source_pose_only, label + " driver policy")
	_check(driver.posture_layer.source_pose_only, label + " posture policy")
	_check(driver.weapon_pose_solver.source_pose_only, label + " weapon presentation policy")
	_check(bool(driver.get_animation_debug_state().get("source_pose_only", false)), label + " observable policy")
	_check(not driver.animation_tree.tree_root.has_node(&"legacy_pistol_upper"), label + " no legacy upper graph node")


func _check_native(driver, clip: StringName, label: String) -> void:
	native_route_checks += 1
	_check(driver.available_clips.has(clip), label + " resolved clip exists")
	if not driver.available_clips.has(clip):
		return
	var animation: Animation = driver.animation_player.get_animation(clip)
	var source := String(animation.get_meta("source_name", ""))
	_check(source.begins_with("seal_p"), label + " original pistol source, got " + source + " via " + String(clip))
	_check(animation.get_track_count() > 0, label + " has actual pose tracks")
	_check(not String(clip).begins_with("legacy_"), label + " no legacy clip fallback")


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)


func _finish(pistols: int, families: Array) -> void:
	print("SOURCE_POSE_ONLY_PROFILE ", "PASS" if failures.is_empty() else "FAIL", " ", JSON.stringify({"pistols": pistols, "families": families, "native_route_checks": native_route_checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
