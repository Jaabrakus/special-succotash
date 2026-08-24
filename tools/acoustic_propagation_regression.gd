extends SceneTree

const Profile := preload("res://scripts/audio/acoustic_propagation_profile.gd")
const Solver := preload("res://scripts/audio/acoustic_propagation_solver.gd")
const RuntimeAudio := preload("res://scripts/audio/lab_leak_audio_engine.gd")
const AcousticEngine := preload("res://scripts/audio/acoustic_propagation_engine.gd")


func _init() -> void:
	var profile := Profile.new()
	if not profile.load_from_file():
		push_error("Acoustic profile did not load")
		quit(1)
		return
	var errors := profile.validate()
	if not errors.is_empty():
		push_error("Acoustic profile validation failed: %s" % ", ".join(errors))
		quit(1)
		return
	for event_class in [&"weapon", &"body_impact", &"footstep", &"foley"]:
		var policy := profile.policy_for(event_class)
		if policy.is_empty() or float(policy.get("max_distance_m", 0.0)) <= 0.0:
			push_error("Missing production event policy: %s" % event_class)
			quit(1)
			return
	var solver := Solver.new()
	var portals: Array[Dictionary] = [{
		"id": "door_a",
		"from_zone": &"room_a",
		"to_zone": &"outside",
		"position": Vector3(4.0, 1.2, 0.0),
		"open": true,
		"bidirectional": true,
	}]
	var routed := solver.solve(
		&"room_a", &"outside", Vector3.ZERO, Vector3(9.0, 0.0, 2.0), portals, false, profile
	)
	if StringName(routed.get("kind", &"")) != &"portal":
		push_error("Open doorway did not produce a portal route")
		quit(1)
		return
	if int(routed.get("portal_hops", 0)) != 1:
		push_error("Portal hop count is incorrect")
		quit(1)
		return
	portals[0]["open"] = false
	var blocked := solver.solve(
		&"room_a", &"outside", Vector3.ZERO, Vector3(9.0, 0.0, 2.0), portals, false, profile
	)
	if StringName(blocked.get("kind", &"")) != &"blocked":
		push_error("Closed doorway did not fall back to wall transmission")
		quit(1)
		return
	if float(blocked.get("lowpass_hz", 99999.0)) >= float(routed.get("lowpass_hz", 0.0)):
		push_error("Blocked route must remove more high frequencies than an open doorway")
		quit(1)
		return
	var direct := solver.solve(
		&"outside", &"outside", Vector3.ZERO, Vector3(3.0, 0.0, 0.0), [], true, profile
	)
	if StringName(direct.get("kind", &"")) != &"direct":
		push_error("Clear path did not remain direct")
		quit(1)
		return
	var engine_source := _read("res://scripts/audio/acoustic_propagation_engine.gd")
	var runtime_audio_source := _read("res://scripts/audio/lab_leak_audio_engine.gd")
	var weapon_runtime_source := _read("res://scripts/runtime/main_weapon_runtime.gd")
	var training_world_source := _read("res://scripts/runtime/main_training_world.gd")
	var multiplayer_audio_source := _read(
		"res://scripts/network/socom_multiplayer_rounds.gd"
	)
	if "AcousticWeaponDirect" not in engine_source:
		push_error("Direct weapon shots do not use the shared acoustic reflection bus")
		quit(1)
		return
	if "origin, false, _local_acoustic_exclusions()" not in weapon_runtime_source:
		push_error("Gameplay still bypasses acoustic route solving for rifle fire")
		quit(1)
		return
	if "play_hit_confirm(" in weapon_runtime_source:
		push_error("Gameplay still overlays the synthetic hit-confirm chime")
		quit(1)
		return
	if '"body_impact", {"direct_clear": true}' in runtime_audio_source:
		push_error("Body impacts still bypass wall and room filtering")
		quit(1)
		return
	if "880.0" in runtime_audio_source or "1740.0" in runtime_audio_source:
		push_error("Head impacts still contain the old metallic confirmation ring")
		quit(1)
		return
	if "sin(TAU * 56.0 * t)" not in runtime_audio_source:
		push_error("Head impacts are missing the approved low-frequency dud layer")
		quit(1)
		return
	if "configure_map" not in training_world_source:
		push_error("Training maps do not configure acoustic rooms and portals")
		quit(1)
		return
	if (
		"AudioEngine.play_gunshot" not in multiplayer_audio_source
		or "AudioEngine.play_body_impact" not in multiplayer_audio_source
	):
		push_error("Replicated multiplayer shots bypass acoustic propagation")
		quit(1)
		return
	var engine := AcousticEngine.new()
	engine.profile = profile
	engine.solver = solver
	root.add_child(engine)
	engine.configure_map({"objects": [
		{
			"id": "room_floor", "type": "floor",
			"position": {"x": 2.0, "y": 0.1, "z": 3.0},
			"size": {"x": 8.0, "y": 0.2, "z": 6.0},
			"properties": {"group_id": "test_room"},
		},
		{
			"id": "room_roof", "type": "roof",
			"position": {"x": 2.0, "y": 3.1, "z": 3.0},
			"size": {"x": 8.0, "y": 0.2, "z": 6.0},
			"properties": {"group_id": "test_room"},
		},
		{
			"id": "room_door", "type": "doorway_wall",
			"position": {"x": 2.0, "y": 1.5, "z": 6.0},
			"size": {"x": 8.0, "y": 3.0, "z": 0.3},
			"properties": {"group_id": "test_room"},
		},
	]})
	if engine.acoustic_zones.size() != 1 or engine.acoustic_portals.size() != 1:
		push_error("Existing grouped map geometry did not infer one room and doorway portal")
		quit(1)
		return
	if RuntimeAudio.body_impact_layers(false).size() != 2:
		push_error("Body impact must contain thump and projectile snap layers")
		quit(1)
		return
	if RuntimeAudio.body_impact_layers(true).size() != 3:
		push_error("Head impact must add a helmet layer")
		quit(1)
		return
	print(
		"ACOUSTIC_PROPAGATION_PASS portal_delay_ms=%.1f blocked_cutoff=%.0f"
		% [float(routed.delay_seconds) * 1000.0, float(blocked.lowpass_hz)]
	)
	quit(0)


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""
