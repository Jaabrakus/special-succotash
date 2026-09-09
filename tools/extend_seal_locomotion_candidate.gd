extends SceneTree

const SOURCE := "res://assets/animations/seal_reference/"
const OUTPUT := "res://assets/animations/seal_gameplay/"
const MAP_PATH := "res://config/animation_presets/seal_gameplay_candidate.json"
const PAIRS := {
	"pistol_run_left": ["seal_p_run_90l", "seal_run_90l"],
	"pistol_run_right": ["seal_p_run_90r", "seal_run_90r"],
	"pistol_crouch_forward": ["seal_p_crouchwalk", "seal_crouchwalk"],
	"pistol_crouch_backward": ["seal_p_crouchwalk_bw", "seal_crouchwalk_bw"],
	"pistol_crouch_left": ["seal_p_crouchstrafe_left", "seal_crouchstrafe_left"],
	"pistol_crouch_right": ["seal_p_crouchstrafe_right", "seal_crouchstrafe_right_fast"],
	"pistol_jump_down": ["seal_p_land_soft", ""],
}
const ROUTES := {
	"locomotion/run_left": "pistol_run_left", "locomotion/run_right": "pistol_run_right",
	"locomotion/crouch_forward": "pistol_crouch_forward", "locomotion/crouch_backward": "pistol_crouch_backward",
	"locomotion/crouch_left": "pistol_crouch_left", "locomotion/crouch_right": "pistol_crouch_right",
	"jump_up": "pistol_jump", "jump_up_standing": "pistol_jump",
	"jump_loop": "jump_loop", "jump_down": "pistol_jump_down",
}

func _initialize() -> void:
	extend_candidate()
	quit()

static func compose(upper: Animation, base: Animation) -> Animation:
	var result := upper.duplicate(true) as Animation
	if base == null:
		return result
	for track in base.get_track_count():
		if result.find_track(base.track_get_path(track), base.track_get_type(track)) >= 0:
			continue
		var index := result.add_track(base.track_get_type(track))
		result.track_set_path(index, base.track_get_path(track))
		result.track_set_interpolation_type(index, base.track_get_interpolation_type(track))
		result.track_set_interpolation_loop_wrap(index, base.track_get_interpolation_loop_wrap(track))
		for key in base.track_get_key_count(track):
			result.track_insert_key(index, base.track_get_key_time(track, key) / base.length * result.length,
				base.track_get_key_value(track, key))
	result.set_meta("source_coverage", "composed_full")
	result.set_meta("seal_composite_base", base.get_meta("source_name", ""))
	return result

static func extend_candidate() -> void:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUTPUT + "manifest.json"))
	# Validate all destinations first; do not overwrite previously reviewed assets.
	for slot: String in PAIRS:
		assert(not FileAccess.file_exists(OUTPUT + slot + ".tres"), "Candidate extension already exists: " + slot)
	for slot: String in PAIRS:
		var pair: Array = PAIRS[slot]
		var upper := load(SOURCE + pair[0] + ".tres") as Animation
		var base := load(SOURCE + pair[1] + ".tres") as Animation if pair[1] != "" else null
		var clip := compose(upper, base)
		var path := OUTPUT + slot + ".tres"
		assert(ResourceSaver.save(clip, path) == OK)
		map.clips[slot] = path
		manifest.states[slot] = {"source": pair[0], "base": pair[1], "path": path,
			"kind": "phase-matched missing-track composition" if base != null else "full", "duration": clip.length}
	for slot: String in ROUTES:
		map.family_animation_slots.TWO_HAND_PISTOL[slot] = ROUTES[slot]
	map.locomotion.preserve_source_locomotion = true
	map.jump_lower_body.enabled = false
	manifest.locomotion_note = "Standing/crouch diagonals blend native cardinal clips; legacy diagonal assets are inactive in this graph. No separate pistol in-air clip was recovered: shared seal_runningjump_in_air is explicit. No exact held weapon parent/angle recovery yet."
	for output_path: String in [MAP_PATH, OUTPUT + "manifest.json"]:
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		assert(file != null)
		file.store_string(JSON.stringify(map if output_path == MAP_PATH else manifest, "\t") + "\n")
		file.close()
	print("SEAL_LOCOMOTION_EXTEND PASS added=", PAIRS.size())
