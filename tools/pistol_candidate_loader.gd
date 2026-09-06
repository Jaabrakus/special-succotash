extends RefCounted

## Test-only injection. Never writes the shared profile or existing source clips.
var scene: Node
var action: Animation
var low_action: Animation
var source_skeleton: Skeleton3D
var last_rest_error := 0.0
var last_track_count := 0

func load_candidate(path: String) -> bool:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path, state) != OK:
		return false
	scene = document.generate_scene(state)
	var runtime = load("res://scripts/player/operator_asset_runtime.gd").new()
	source_skeleton = runtime.call("_find_skeleton", scene)
	var player: AnimationPlayer = runtime.call("_find_animation_player", scene)
	if player != null:
		for name: StringName in player.get_animation_list():
			if "PistolReadySquare_Candidate" in String(name):
				action = player.get_animation(name)
			if "PistolLowReady_Candidate" in String(name):
				low_action = player.get_animation(name)
	# Preserve the already-verified high action exactly. LOW is composed over a
	# different base idle, so its explicit static parent rotations are required:
	# removing them would silently keep the old Spine/Shoulder pose underneath.
	var low_document := GLTFDocument.new()
	var low_state := GLTFState.new()
	if low_document.append_from_file(path, low_state) != OK:
		return false
	var complete_scene := low_document.generate_scene(low_state, 30.0, false, false)
	var complete_player: AnimationPlayer = runtime.call("_find_animation_player", complete_scene)
	if complete_player != null:
		for name: StringName in complete_player.get_animation_list():
			if "PistolLowReady_Candidate" in String(name):
				low_action = complete_player.get_animation(name).duplicate() as Animation
	complete_scene.free()
	return action != null and source_skeleton != null

func install(driver: Node, separate_idle: bool = false) -> Dictionary:
	var library: AnimationLibrary = driver.get("dynamic_anim_lib")
	var target_skeleton: Skeleton3D = driver.get("skeleton")
	last_track_count = 0
	last_rest_error = 0.0
	for clip in [&"pistol_idle", &"pistol_idle_kneeling"]:
		var original := library.get_animation(clip)
		var composite := compose(original, target_skeleton, action)
		if last_rest_error > 0.1:
			return {"ok": false, "rest_error_deg": last_rest_error}
		var ready_clip: StringName = StringName(String(clip) + "_ready") if separate_idle else clip
		if library.has_animation(ready_clip):
			library.remove_animation(ready_clip)
		library.add_animation(ready_clip, composite)
		if separate_idle:
			if low_action == null:
				return {"ok": false, "error": "missing low-ready action"}
			var low := compose(original, target_skeleton, low_action)
			library.remove_animation(clip)
			library.add_animation(clip, low)
			var available: Dictionary = driver.get("available_clips")
			available[ready_clip] = true
			var handling: Dictionary = driver.get("equipped_weapon_handling_profile")
			var slots: Dictionary = handling.get("animation_slots", {})
			slots["ready_standing" if clip == &"pistol_idle" else "ready_crouched"] = String(ready_clip)
			handling["animation_slots"] = slots
	if separate_idle:
		driver.call("_build_animation_tree")
	return {"ok": last_track_count >= 16, "tracks": last_track_count, "rest_error_deg": last_rest_error}

func compose(original: Animation, target_skeleton: Skeleton3D, source_action: Animation) -> Animation:
	var composite := original.duplicate() as Animation
	for source_track in range(source_action.get_track_count()):
		if source_action.track_get_type(source_track) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := String(source_action.track_get_path(source_track)).get_slice(":", 1)
		if bone.ends_with("Hips") or "Leg" in bone or "Foot" in bone or "Toe" in bone or bone.ends_with("Root"):
			continue
		var target_index := target_skeleton.find_bone(bone)
		var source_index := source_skeleton.find_bone(bone)
		if target_index < 0 or source_index < 0:
			continue
		var source_rest := source_skeleton.get_bone_rest(source_index).basis.get_rotation_quaternion()
		var target_rest := target_skeleton.get_bone_rest(target_index).basis.get_rotation_quaternion()
		last_rest_error = maxf(last_rest_error, rad_to_deg(source_rest.angle_to(target_rest)))
		var path := NodePath(".:" + bone)
		var track := composite.find_track(path, Animation.TYPE_ROTATION_3D)
		if track < 0:
			track = composite.add_track(Animation.TYPE_ROTATION_3D)
			composite.track_set_path(track, path)
		for key in range(composite.track_get_key_count(track) - 1, -1, -1):
			composite.track_remove_key(track, key)
		composite.track_insert_key(track, 0.0, source_action.rotation_track_interpolate(source_track, 0.0))
		last_track_count += 1
	return composite

func dispose() -> void:
	if scene != null:
		scene.free()
		scene = null
