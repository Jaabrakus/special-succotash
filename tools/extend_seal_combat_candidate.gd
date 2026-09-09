extends SceneTree

const CANDIDATE := "res://config/animation_presets/seal_gameplay_candidate.json"
const MANIFEST := "res://assets/animations/seal_gameplay/manifest.json"
const MAP := {
	"combat_fire": "seal_recoil", "crouch_fire": "seal_crouch_recoil",
	"prone_fire": "seal_prone_recoil", "pistol_fire": "seal_p_recoil",
	"pistol_prone_fire": "seal_p_prone_recoil", "pistol_idle_prone": "seal_p_prone",
}
const READY := {
	"aim_idle": "seal_recoil", "aim_idle_crouch": "seal_crouch_recoil",
	"pistol_recovery_reference_standing": "seal_p_recoil",
	"pistol_recovery_reference_crouched": "seal_p_recoil",
}

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--ready-only"):
		extend_ready()
	else:
		extend_candidate()
	quit()

static func extend_candidate() -> void:
	var candidate: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CANDIDATE))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert(not candidate.is_empty() and not manifest.is_empty())
	# Preflight every destination: never overwrite any existing animation.
	for state: String in MAP:
		var path := "res://assets/animations/seal_gameplay/" + state + ".tres"
		assert(not FileAccess.file_exists(path), "Combat extension already exists: " + path)
	for state: String in MAP:
		var source: String = MAP[state]
		var clip := (load("res://assets/animations/seal_reference/" + source + ".tres") as Animation).duplicate(true) as Animation
		assert(clip.get_meta("source_coverage", "") == "full")
		clip.loop_mode = Animation.LOOP_NONE
		var path := "res://assets/animations/seal_gameplay/" + state + ".tres"
		assert(ResourceSaver.save(clip, path) == OK)
		candidate.clips[state] = path
		manifest.states[state] = {"source": source, "path": path, "kind": "full", "duration": clip.length, "timing": "source"}
		manifest.unconverted.erase(state)
		for section in ["clip_aliases", "mirrored_clips", "leg_mirrored_clips", "pose_yaw_offsets_degrees"]:
			candidate[section].erase(state)
		if state.ends_with("fire"):
			candidate.state_rules[state] = {"layer": "UPPER_BODY", "blend_in_seconds": 0.01, "blend_out_seconds": 0.025, "return_state": "CURRENT_BASE"}
	var rifle := {"STANDING": "combat_fire", "CROUCHED": "crouch_fire", "PRONE": "prone_fire"}
	var pistol := {"STANDING": "pistol_fire", "CROUCHED": "pistol_fire", "PRONE": "pistol_prone_fire"}
	var fire: Dictionary = candidate.event_routes.FIRE_ACCEPTED
	fire.default_state = "combat_fire"
	fire.posture_states = rifle.duplicate(true)
	fire.family_states.TWO_HAND_RIFLE = {"default_state": "combat_fire", "posture_states": rifle}
	fire.family_states.TWO_HAND_PISTOL = {"default_state": "pistol_fire", "posture_states": pistol}
	candidate.family_animation_slots = {"TWO_HAND_PISTOL": {"idle_prone": "pistol_idle_prone"}}
	candidate.event_routes.WEAPON_EQUIPPED.family_states.TWO_HAND_PISTOL = {
		"default_state": "pistol_idle", "posture_states": {"STANDING": "pistol_idle", "CROUCHED": "pistol_idle_kneeling", "PRONE": "pistol_idle_prone"}}
	manifest.combat_note = "Crouched pistol uses standing pistol recoil through the existing upper-body-only fire mask; crouched base remains. No separate crouched pistol recoil was extracted."
	for pair in [[CANDIDATE, candidate], [MANIFEST, manifest]]:
		var file := FileAccess.open(pair[0], FileAccess.WRITE)
		assert(file != null)
		file.store_string(JSON.stringify(pair[1], "\t") + "\n")
	print("SEAL_COMBAT_CANDIDATE extended=", MAP.size(), " total=", manifest.states.size(), " main_map_unchanged=true")
	extend_ready()

static func extend_ready() -> void:
	var candidate: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CANDIDATE))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	for state: String in READY:
		assert(not FileAccess.file_exists("res://assets/animations/seal_gameplay/held_" + state + ".tres"), "Held-ready output already exists")
	for state: String in READY:
		var source: String = READY[state]
		var clip := (load("res://assets/animations/seal_reference/" + source + ".tres") as Animation).duplicate(true) as Animation
		for track in clip.get_track_count():
			# Keep exactly the original pre-recoil sample, not a hand-authored pose.
			for key in range(clip.track_get_key_count(track) - 1, 0, -1):
				clip.track_remove_key(track, key)
		clip.length = 1.0 / 30.0
		clip.loop_mode = Animation.LOOP_NONE
		clip.set_meta("seal_held_source_time", 0.0)
		var path := "res://assets/animations/seal_gameplay/held_" + state + ".tres"
		assert(ResourceSaver.save(clip, path) == OK)
		candidate.clips[state] = path
		manifest.states[state] = {"source": source, "path": path, "kind": "held pre-recoil source frame", "duration": clip.length, "source_time": 0.0}
	candidate.family_animation_slots.TWO_HAND_PISTOL.merge({
		"idle_standing": "pistol_compressed_idle_standing",
		"idle_standing_moving": "pistol_idle",
		"idle_crouched": "pistol_compressed_idle_crouched",
		"ready_standing": "pistol_recovery_reference_standing",
		"ready_crouched": "pistol_recovery_reference_crouched",
		"ready_standing_moving": "pistol_recovery_reference_standing",
		"ready_crouched_moving": "pistol_recovery_reference_crouched"}, true)
	for pair in [[CANDIDATE, candidate], [MANIFEST, manifest]]:
		var file := FileAccess.open(pair[0], FileAccess.WRITE)
		assert(file != null)
		file.store_string(JSON.stringify(pair[1], "\t") + "\n")
	print("SEAL_HELD_READY source_frames=", READY.size(), " main_map_unchanged=true")
