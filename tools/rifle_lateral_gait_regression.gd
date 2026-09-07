extends SceneTree

const Profile := preload("res://scripts/player/operator_animation_profile.gd")
const Cache := preload("res://scripts/player/operator_animation_library_cache.gd")
const ALIASES := {
	&"run_lateral_left": &"run_forward", &"run_lateral_right": &"run_forward",
	&"crouch_lateral_left": &"crouch_forward", &"crouch_lateral_right": &"crouch_forward",
}
const SLOTS := {"run_left": "run_lateral_left", "run_right": "run_lateral_right", "crouch_left": "crouch_lateral_left", "crouch_right": "crouch_lateral_right"}
var failures: Array[String] = []
var scene: Node3D
var player: CharacterBody3D
var driver: Node
var controller: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	scene = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(65)
	player = scene.get_node("Player")
	driver = player.get_node("Mannequin/ProductionAnimation")
	controller = scene.get_node("WeaponController")
	player.set_physics_process(false)
	player.get_node("Mannequin").set_process(false)
	_check_aliases()
	for weapon: String in ["ak-47", "m4a1", "m16a2", "mark_23"]:
		_check(bool(controller.call("apply_authorized_weapon_pickup", "res://config/weapons/%s.json" % weapon)), weapon + " canonical equip")
		await _frames(20)
		var selected := weapon in ["ak-47", "m4a1"]
		var graph = driver.get("locomotion_graph")
		var slots: Dictionary = driver.get("equipped_weapon_handling_profile").get("locomotion_slots", {})
		for slot: String in SLOTS:
			var actual := String(slots.get(slot, ""))
			_check((actual == SLOTS[slot]) if selected else (not ALIASES.has(StringName(actual))), weapon + " resolved slot scope " + slot)
			var resolved: StringName = graph._weapon_locomotion_clip(slot, StringName(slot), driver.get("available_clips"))
			_check((resolved == StringName(SLOTS[slot])) if selected else (not ALIASES.has(resolved)), weapon + " actual graph route " + slot)
		if selected:
			for posture: StringName in [&"STANDING", &"CROUCHED"]:
				await _check_phase(weapon, posture)
	_check_geometry()
	print("RIFLE_LATERAL_GAIT_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)


func _check_aliases() -> void:
	var profile = driver.get("animation_profile")
	var library: AnimationLibrary = driver.get("dynamic_anim_lib")
	_check(String(library.get_meta("socom_fingerprint", "")) == Cache.new().fingerprint_for(profile), "canonical animation library matches current saved fingerprint")
	for name: StringName in ALIASES:
		_check(library.has_animation(name), String(name) + " not missing from a stale cache")
		if not library.has_animation(name):
			continue
		var source: Animation = library.get_animation(ALIASES[name])
		var alias: Animation = library.get_animation(name)
		_check(alias.loop_mode == Animation.LOOP_LINEAR and is_equal_approx(alias.length, source.length), String(name) + " preserves source cycle and looping")
		_check(String(driver.get("source_animation_names").get(name, "")) == "alias:" + String(ALIASES[name]), String(name) + " is processed from the canonical forward source")
		_check(is_equal_approx(absf(profile.pose_yaw_offset_degrees(name)), 90.0), String(name) + " accepts explicit full lateral rotation")
		_check(alias.get_track_count() == source.get_track_count(), String(name) + " preserves source track layout")
		var yaw := Quaternion(Vector3.UP, deg_to_rad(profile.pose_yaw_offset_degrees(name)))
		for track in source.get_track_count():
			_check(alias.track_get_path(track) == source.track_get_path(track) and alias.track_get_type(track) == source.track_get_type(track), "alias track identity unchanged")
			_check(alias.track_get_key_count(track) == source.track_get_key_count(track), "alias key count unchanged")
			var hips := String(source.track_get_path(track)).ends_with(":mixamorig_Hips") and source.track_get_type(track) == Animation.TYPE_ROTATION_3D
			for key in source.track_get_key_count(track):
				_check(is_equal_approx(alias.track_get_key_time(track, key), source.track_get_key_time(track, key)), "alias key times preserve phase")
				var before: Variant = source.track_get_key_value(track, key)
				var after: Variant = alias.track_get_key_value(track, key)
				if hips:
					_check(_basis_error(Basis(after), Basis((yaw * (before as Quaternion)).normalized())) < 0.00001, String(name) + " hip key equals yaw times source")
				else:
					_check(before == after, String(name) + " every non-hip local key is unchanged")
	_check(profile.pose_yaw_offset_degrees(&"run_left") == 24.0 and profile.pose_yaw_offset_degrees(&"crouch_left") == 18.0, "original lateral clips remain unchanged")


func _check_phase(weapon: String, posture: StringName) -> void:
	player.call("_try_set_posture", 0 if posture == &"STANDING" else 1)
	_input(Vector2.LEFT, posture)
	await _frames(45)
	var tree: AnimationTree = driver.get("animation_tree")
	var path := "parameters/full_space" if posture == &"STANDING" else "parameters/crouch_space"
	var previous := -1.0
	var travel := 0.0
	for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.LEFT, Vector2.RIGHT, Vector2(-0.7071,0.7071), Vector2(0.7071,0.7071)]:
		_input(direction, posture)
		for frame in 24:
			await process_frame
			var length := float(tree.get(path + "/current_length"))
			_check(length > 0.0, "actual blendspace exposes a positive cycle length")
			var phase := float(tree.get(path + "/current_position")) / maxf(length, 0.0001)
			if previous >= 0.0:
				var step := fposmod(phase - previous, 1.0)
				_check(step < 0.15, weapon + " " + String(posture) + " direction change preserves gait phase")
				travel += step
			previous = phase
			_check(not bool(driver.get("locomotion_graph").jump_lower_body_active), "ground gait does not trigger the jump layer")
	_check(travel > 0.3, weapon + " " + String(posture) + " gait is not frozen")
	print("RIFLE_LATERAL_PHASE ", weapon, " ", posture, " travelled_cycles=", travel)


func _check_geometry() -> void:
	driver.set_process(false)
	driver.get("animation_tree").active = false
	var animations: AnimationPlayer = driver.get("animation_player")
	var skeleton: Skeleton3D = driver.get("skeleton")
	animations.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for name: StringName in ALIASES:
		var animation := animations.get_animation(name)
		if animation == null:
			continue
		var max_error := 0.0
		for index in 64:
			var time := animation.length * float(index) / 64.0
			var base := _sample_vectors(animations, skeleton, ALIASES[name], time)
			var turned := _sample_vectors(animations, skeleton, name, time)
			for key: String in ["hips", "left_foot", "right_foot"]:
				var before: Vector3 = base[key]
				var after: Vector3 = turned[key]
				if Vector2(before.x, before.z).length() < 0.0001:
					continue
				before.y = 0.0
				after.y = 0.0
				var expected: float = deg_to_rad(driver.get("animation_profile").pose_yaw_offset_degrees(name))
				var error := absf(wrapf(before.signed_angle_to(after, Vector3.UP) - expected, -PI, PI))
				max_error = maxf(max_error, rad_to_deg(error))
		_check(max_error < 0.02, String(name) + " actual hips and toe directions turn ninety degrees at matching phases")
		print("RIFLE_LATERAL_GEOMETRY ", name, " maximum_relative_yaw_error_deg=", max_error)


func _sample_vectors(animations: AnimationPlayer, skeleton: Skeleton3D, clip: StringName, time: float) -> Dictionary:
	skeleton.clear_bones_global_pose_override()
	skeleton.reset_bone_poses()
	animations.play(clip)
	animations.seek(time, true)
	skeleton.force_update_all_bone_transforms()
	return {"hips": _pos(skeleton, &"mixamorig_RightUpLeg") - _pos(skeleton, &"mixamorig_LeftUpLeg"), "left_foot": _pos(skeleton, &"mixamorig_LeftToeBase") - _pos(skeleton, &"mixamorig_LeftFoot"), "right_foot": _pos(skeleton, &"mixamorig_RightToeBase") - _pos(skeleton, &"mixamorig_RightFoot")}


func _pos(skeleton: Skeleton3D, bone: StringName) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin


func _basis_error(a: Basis, b: Basis) -> float:
	return maxf(a.x.distance_to(b.x), maxf(a.y.distance_to(b.y), a.z.distance_to(b.z)))


func _input(direction: Vector2, posture: StringName) -> void:
	var target := player.global_position + Vector3(0.0, 1.4 if posture == &"STANDING" else 1.0, -25.0)
	driver.call("set_visual_inputs", direction, posture, 0.0, 0.0, 0.0, false, 0.0, 1.0, &"LOCOMOTION", 0.0, &"FULL" if posture == &"STANDING" else &"WALK", 6.5 if posture == &"STANDING" else 2.6, target)


func _frames(count: int) -> void:
	for frame in count:
		await process_frame


func _check(condition: bool, label: String) -> void:
	if not condition and not failures.has(label):
		failures.append(label)
		push_error("RIFLE_LATERAL_GAIT " + label)
