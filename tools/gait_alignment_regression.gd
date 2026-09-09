extends SceneTree

const Alignment := preload("res://scripts/player/operator_gait_alignment.gd")
const Profile := preload("res://scripts/player/operator_animation_profile.gd")
const Cache := preload("res://scripts/player/operator_animation_library_cache.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var model: Node = (load(Cache.TARGET_RIG_PATH) as PackedScene).instantiate()
	var rig := _find_rig(model)
	var profile := Profile.new()
	profile.load_project_map()
	for name in ["run_forward", "run_backward", "run_left", "run_right", "crouch_forward", "crouch_backward", "crouch_left", "crouch_right", "pistol_run_forward"]:
		var source: Animation = load(profile.clip_paths[StringName(name)])
		var copy := source.duplicate(true) as Animation
		Alignment.align_support(copy, rig, 0.05 / 62.0)
		_expect(copy.get_meta("grounded_gait_aligned", false), name + " aligned")
		var hips := copy.find_track(NodePath(".:mixamorig_Hips"), Animation.TYPE_POSITION_3D)
		for track in source.get_track_count():
			_expect(copy.track_get_key_count(track) == source.track_get_key_count(track), name + " key count retained")
			for key in source.track_get_key_count(track):
				_expect(copy.track_get_key_time(track, key) == source.track_get_key_time(track, key), name + " timing retained")
				if track != hips:
					_expect(copy.track_get_key_value(track, key) == source.track_get_key_value(track, key), name + " non-root poses retained")
		_expect(not source.has_meta("grounded_gait_aligned"), name + " source untouched")
		_expect(copy.length == source.length and copy.loop_mode == source.loop_mode, name + " duration/loop retained")
	var jump: Animation = load(profile.clip_paths[&"jump_up"])
	var jump_copy := jump.duplicate(true) as Animation
	jump_copy.loop_mode = Animation.LOOP_NONE
	Alignment.align_support(jump_copy, rig, 0.05 / 62.0)
	_expect(not jump_copy.has_meta("grounded_gait_aligned"), "one-shot is excluded")
	var fingerprint := Cache.new().fingerprint_for(profile)
	profile.locomotion.gait_support_height_m = 0.08
	_expect(Cache.new().fingerprint_for(profile) != fingerprint, "height change invalidates cached clips")
	profile.locomotion.gait_support_height_m = 0.05
	profile.locomotion.grounded_gait_alignment = false
	_expect(Cache.new().fingerprint_for(profile) != fingerprint, "alignment toggle invalidates cached clips")
	model.free()
	print("GAIT_ALIGNMENT ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _find_rig(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child in node.get_children():
		var found := _find_rig(child)
		if found != null: return found
	return null

func _expect(ok: bool, message: String) -> void:
	if not ok and message not in failures: failures.append(message)
