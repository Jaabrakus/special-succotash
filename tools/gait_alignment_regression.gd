extends SceneTree

const Alignment := preload("res://scripts/player/operator_gait_alignment.gd")
const Profile := preload("res://scripts/player/operator_animation_profile.gd")
const Cache := preload("res://scripts/player/operator_animation_library_cache.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var model: Node = (load(Cache.TARGET_RIG_PATH) as PackedScene).instantiate()
	root.add_child(model)
	var rig := _find_rig(model)
	var profile := Profile.new()
	profile.load_project_map()
	for name in ["run_forward", "run_backward", "run_left", "run_right", "crouch_forward", "crouch_backward", "crouch_left", "crouch_right", "pistol_run_forward"]:
		var source: Animation = load(profile.clip_paths[StringName(name)])
		var copy := source.duplicate(true) as Animation
		Alignment.align_support(copy, rig, 0.05 / 62.0)
		var before_balance := copy.duplicate(true) as Animation
		Alignment.balance_run_support(copy, 0.025 / 62.0)
		_expect(copy.get_meta("grounded_gait_aligned", false), name + " aligned")
		var hips := copy.find_track(NodePath(".:mixamorig_Hips"), Animation.TYPE_POSITION_3D)
		for key in copy.track_get_key_count(hips):
			var delta: Vector3 = copy.track_get_key_value(hips, key) - before_balance.track_get_key_value(hips, key)
			_expect(absf(delta.y) <= 0.025 / 62.0 + 0.000001 and delta.x == 0.0 and delta.z == 0.0, name + " bounded height-only balance")
		for track in source.get_track_count():
			_expect(copy.track_get_key_count(track) == source.track_get_key_count(track), name + " key count retained")
			for key in source.track_get_key_count(track):
				_expect(copy.track_get_key_time(track, key) == source.track_get_key_time(track, key), name + " timing retained")
				if track != hips:
					_expect(copy.track_get_key_value(track, key) == source.track_get_key_value(track, key), name + " non-root poses retained")
		_expect(not source.has_meta("grounded_gait_aligned"), name + " source untouched")
		_expect(copy.length == source.length and copy.loop_mode == source.loop_mode, name + " duration/loop retained")
		if name in ["run_forward", "pistol_run_forward"]: _check_bounce(copy, rig, name)
	var jump: Animation = load(profile.clip_paths[&"jump_up"])
	var jump_copy := jump.duplicate(true) as Animation
	jump_copy.loop_mode = Animation.LOOP_NONE
	Alignment.align_support(jump_copy, rig, 0.05 / 62.0)
	Alignment.balance_run_support(jump_copy, 0.025 / 62.0)
	_expect(not jump_copy.has_meta("forward_run_hip_balanced"), "one-shot balance is excluded")
	_expect(not jump_copy.has_meta("grounded_gait_aligned"), "one-shot is excluded")
	var fingerprint := Cache.new().fingerprint_for(profile)
	profile.locomotion.forward_run_hip_balance = false
	_expect(Cache.new().fingerprint_for(profile) != fingerprint, "balance toggle invalidates cached clips")
	profile.locomotion.forward_run_hip_balance = true
	profile.locomotion.forward_run_max_hip_travel_m = 0.03
	_expect(Cache.new().fingerprint_for(profile) != fingerprint, "bounce limit invalidates cached clips")
	profile.locomotion.forward_run_max_hip_travel_m = 0.04
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

func _check_bounce(source: Animation, rig: Skeleton3D, name: String) -> void:
	var copy := source.duplicate(true) as Animation
	Alignment.limit_run_bounce(copy, rig, 0.04 / 62.0)
	_expect(copy.get_meta("run_bounce_fit_error_m", INF) * 62.0 < 0.01, name + " bake fits original ankle targets")
	var legs := ["mixamorig_LeftUpLeg", "mixamorig_LeftLeg", "mixamorig_LeftFoot", "mixamorig_RightUpLeg", "mixamorig_RightLeg", "mixamorig_RightFoot"]
	var positions := {}
	var rotations := {}
	for track in source.get_track_count():
		var bone := rig.find_bone(str(source.track_get_path(track)).get_slice(":", 1))
		if bone < 0: continue
		if source.track_get_type(track) == Animation.TYPE_POSITION_3D: positions[bone] = track
		if source.track_get_type(track) == Animation.TYPE_ROTATION_3D: rotations[bone] = track
		if rig.get_bone_name(bone) in legs or rig.get_bone_name(bone) == "mixamorig_Hips": continue
		for key in source.track_get_key_count(track):
			_expect(source.track_get_key_value(track,key) == copy.track_get_key_value(track,key), name + " upper-body tracks preserved")
	var error := 0.0
	for frame in 120:
		var t := source.length * float(frame) / 120.0
		for side in ["mixamorig_LeftFoot", "mixamorig_RightFoot"]:
			var index := rig.find_bone(side)
			var before := Alignment._bone_pose(index,t,source,rig,rotations,positions,{})
			var after := Alignment._bone_pose(index,t,copy,rig,rotations,positions,{})
			error = maxf(error, before.origin.distance_to(after.origin) * 62.0)
	_expect(error < 0.01, name + " interpolated foot path within 1cm")
	_expect(source.length == copy.length and source.loop_mode == copy.loop_mode, name + " bounce fit preserves timing")
	print("RUN_BOUNCE_FIT ", name, " max_interpolated_foot_error_m=", error)
