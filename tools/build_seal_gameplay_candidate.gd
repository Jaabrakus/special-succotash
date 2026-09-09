extends SceneTree

const ROOT := "res://assets/animations/seal_reference/"
const OUTPUT := "res://assets/animations/seal_gameplay/"
const RETARGET = preload("res://scripts/labs/animation_retarget_service.gd")
const AUTHORED_PEEK := {"enabled":true,"families":{"TWO_HAND_RIFLE":{"STANDING":{"left":"res://assets/animations/seal_reference/seal_stand2llean.tres","right":"res://assets/animations/seal_reference/seal_stand2rlean.tres"},"CROUCHED":{"left":"res://assets/animations/seal_reference/seal_crouch2llean.tres","right":"res://assets/animations/seal_reference/seal_crouch2rlean.tres"},"PRONE":{"left":"res://assets/animations/seal_reference/seal_prone2llean.tres","right":"res://assets/animations/seal_reference/seal_prone2rlean.tres"}},"TWO_HAND_PISTOL":{"STANDING":{"left":"res://assets/animations/seal_reference/seal_p_stand2llean.tres","right":"res://assets/animations/seal_reference/seal_p_stand2rlean.tres"},"CROUCHED":{"left":"res://assets/animations/seal_reference/seal_p_crouch2llean.tres","right":"res://assets/animations/seal_reference/seal_p_crouch2rlean.tres"},"PRONE":{"left":"res://assets/animations/seal_reference/seal_p_prone2llean.tres","right":"res://assets/animations/seal_reference/seal_p_prone2rlean.tres"}}}}
const MAP := {
	"idle_rifle": "seal_stand", "aim_idle": "seal_stand",
	"idle_crouch": "seal_crouch", "aim_idle_crouch": "seal_crouch",
	"idle_prone": "seal_prone", "prone_forward": "seal_prone_crawl",
	"run_forward": "seal_run", "run_backward": "seal_run_bw",
	"run_left": "seal_run_90l", "run_right": "seal_run_90r",
	"run_lateral_left": "seal_run_90l", "run_lateral_right": "seal_run_90r",
	"walk_forward": "seal_walk", "walk_backward": "seal_walk_bw",
	"walk_left": "seal_lstrafe", "walk_right": "seal_rstrafe",
	"crouch_forward": "seal_crouchwalk", "crouch_backward": "seal_crouchwalk_bw",
	"crouch_left": "seal_crouchstrafe_left", "crouch_right": "seal_crouchstrafe_right_fast",
	"crouch_lateral_left": "seal_crouchstrafe_left", "crouch_lateral_right": "seal_crouchstrafe_right_fast",
	"prone_turn_left": "seal_prone_lstrafe", "prone_turn_right": "seal_prone_rstrafe",
	"dive_roll": "seal_dive2prone", "jump_slide_prone": "seal_dive2prone", "jump_up": "seal_runningjump_launch",
	"jump_up_standing": "seal_jump", "jump_loop": "seal_runningjump_in_air",
	"jump_forward_action": "seal_runningjump_launch", "jump_down": "seal_land_soft",
	"crouch_to_prone": "seal_crouch2prone",
	"grenade_toss": "seal_tossgrenade", "grenade_throw": "seal_prone_throwgrenade",
	"crouch_grenade_toss": "seal_crouch_throwgrenade",
	"pistol_idle": "seal_p_stand", "pistol_idle_kneeling": "seal_p_crouch",
	"pistol_compressed_idle_standing": "seal_p_stand",
	"pistol_compressed_idle_crouched": "seal_p_crouch",
	"pistol_recovery_reference_standing": "seal_p_stand",
	"pistol_recovery_reference_crouched": "seal_p_crouch",
	"pistol_run_backward": "seal_p_run_bw", "pistol_walk_backward": "seal_p_walk_bw",
	"pistol_jump": "seal_p_runningjump_launch",
	"pistol_jump_alt": "seal_p_runningjump_launch",
}
const COMPOSITES := {
	"pistol_run_forward": ["seal_p_run", "seal_run"],
	"pistol_walk_forward": ["seal_p_walk", "seal_walk"],
	"pistol_strafe_left": ["seal_p_lstrafe", "seal_lstrafe"],
	"pistol_strafe_right": ["seal_p_rstrafe", "seal_rstrafe"],
	"pistol_stand_to_kneel": ["seal_p_stand2crouch", "seal_stand2crouch"],
}

func _initialize() -> void:
	var destination := "res://config/animation_presets/seal_gameplay_candidate.json"
	if DirAccess.dir_exists_absolute(OUTPUT) or FileAccess.file_exists(destination):
		push_error("Candidate already exists; refusing to overwrite")
		quit(1)
		return
	var before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/operator_animation_map.json"))
	var candidate: Dictionary = before.duplicate(true)
	candidate.locomotion.preserve_source_locomotion = true
	candidate.jump_lower_body.enabled = false
	var changed := {}
	var metadata := {"version": 1, "source": "SEAL reference retargets", "states": {},
		"unconverted": [], "status": "candidate, not activated"}
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	for state: String in MAP:
		var source_name: String = MAP[state]
		var animation := (load(ROOT + source_name + ".tres") as Animation).duplicate(true) as Animation
		assert(animation.get_meta("source_coverage", "") == "full", "Full-body state needs complete source: " + state)
		if "grenade" in state:
			# Keep the existing authoritative release/recovery timing contract.
			# Only replace the pose, not the duration driving the grenade cue.
			var old_path: String = before.clips["grenade_toss" if state == "crouch_grenade_toss" else state]
			_retime(animation, _duration(old_path))
		var path := OUTPUT + state + ".tres"
		if source_name == "seal_dive2prone":
			animation = preload("res://tools/seal_dive_clip.gd").build(animation)
			path = OUTPUT + "seal_dive_to_prone.tres"
		assert(ResourceSaver.save(animation, path) == OK)
		changed[state] = path
		metadata.states[state] = {"source": source_name, "path": path, "kind": "full",
			"duration": animation.length, "timing": "existing gameplay" if "grenade" in state else "source"}
	for state: String in COMPOSITES:
		var pair: Array = COMPOSITES[state]
		var upper := load(ROOT + pair[0] + ".tres") as Animation
		var base := load(ROOT + pair[1] + ".tres") as Animation
		var result := upper.duplicate(true) as Animation
		var existing := {}
		for track in result.get_track_count():
			existing[str(result.track_get_path(track)) + str(result.track_get_type(track))] = true
		# Fill only missing typed tracks. Preserve every actual upper-body channel.
		for track in base.get_track_count():
			if existing.has(str(base.track_get_path(track)) + str(base.track_get_type(track))):
				continue
			var index := result.add_track(base.track_get_type(track))
			result.track_set_path(index, base.track_get_path(track))
			for key in base.track_get_key_count(track):
				result.track_insert_key(index, base.track_get_key_time(track, key) / base.length * result.length,
					base.track_get_key_value(track, key))
		result.set_meta("source_coverage", "composed_full")
		result.set_meta("seal_composite_base", pair[1])
		var path := OUTPUT + state + ".tres"
		assert(ResourceSaver.save(result, path) == OK)
		changed[state] = path
		metadata.states[state] = {"source": pair[0], "base": pair[1], "path": path,
			"kind": "phase-matched missing-track composition", "duration": result.length}
	for state: String in changed:
		candidate.clips[state] = changed[state]
		for section: String in ["clip_aliases", "mirrored_clips", "leg_mirrored_clips", "pose_yaw_offsets_degrees"]:
			candidate[section].erase(state)
	for state: String in before.clips:
		if not changed.has(state):
			metadata.unconverted.append(state)
	candidate.description = "SEAL gameplay candidate. Existing unmatched states remain original; no new movement or damage authority."
	candidate.authored_peek = AUTHORED_PEEK.duplicate(true)
	_write(destination, candidate)
	_write(OUTPUT + "manifest.json", metadata)
	preload("res://tools/extend_seal_combat_candidate.gd").extend_candidate()
	preload("res://tools/extend_seal_locomotion_candidate.gd").extend_candidate()
	preload("res://tools/extend_seal_firing_candidate.gd").extend_candidate()
	print("SEAL_GAMEPLAY_CANDIDATE states=", changed.size(), " fallback_states=", metadata.unconverted.size())
	quit()

static func _duration(path: String) -> float:
	var resource := load(path)
	if resource is Animation:
		return resource.length
	var scene := (resource as PackedScene).instantiate()
	var service = RETARGET.new()
	var player: AnimationPlayer = service._find_animation_player(scene)
	var result := player.get_animation(service._select_source_animation_name(player)).length
	scene.free()
	return result

func _retime(animation: Animation, duration: float) -> void:
	var original := animation.length
	for track in animation.get_track_count():
		var values: Array = []
		for key in animation.track_get_key_count(track):
			values.append([animation.track_get_key_time(track, key) / original * duration,
				animation.track_get_key_value(track, key)])
		for key in range(animation.track_get_key_count(track) - 1, -1, -1):
			animation.track_remove_key(track, key)
		for value: Array in values:
			animation.track_insert_key(track, value[0], value[1])
	animation.length = duration
	animation.set_meta("seal_source_duration", original)

func _write(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(value, "\t") + "\n")
	file.close()
