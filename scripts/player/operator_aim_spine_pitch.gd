extends RefCounted

## Owned by PostureLayer. Rotates only the upper chain, before hand fitting.
const CHAIN := [&"spine", &"spine1", &"spine2"]
const WEIGHTS := [0.25, 0.35, 0.40]
var applied: Dictionary = {}
var smoothed_pitch := 0.0
var last_pitch_rad := 0.0
var last_bone_count := 0
var last_reason := "not_sampled"
var last_protected_delta := 0.0
var last_spine_delta := 0.0
var last_input_pitch_rad := 0.0


func retire(skeleton: Skeleton3D) -> void:
	# If the graph has written a new pose, it owns that value. Only undo an
	# unchanged value left by this helper (paused/sparse graph, repeated call).
	if is_instance_valid(skeleton):
		for index: int in applied:
			var row: Dictionary = applied[index]
			if skeleton.get_bone_pose_rotation(index).is_equal_approx(row.after):
				skeleton.set_bone_pose_rotation(index, row.before)
	applied.clear()
	last_pitch_rad = 0.0
	last_bone_count = 0
	last_protected_delta = 0.0
	last_spine_delta = 0.0
	last_reason = "suppressed"


func enabled(profile: Dictionary) -> bool:
	return bool(profile.get("enabled", false))


func apply(layer: RefCounted, profile: Dictionary, pitch: float, posture: StringName,
		allowed: bool, aim_world: Vector3, delta: float) -> void:
	var skeleton: Skeleton3D = layer.skeleton
	retire(skeleton)
	last_input_pitch_rad = pitch
	if not is_instance_valid(skeleton) or not enabled(profile) or not allowed or not is_finite(pitch):
		smoothed_pitch = 0.0
		return
	var settings: Variant = profile.get(String(posture).to_lower(), null)
	if not settings is Dictionary:
		smoothed_pitch = 0.0
		return
	var gain := _finite_number(settings, "gain", 0.0, 0.0, 1.0)
	var up := deg_to_rad(_finite_number(settings, "up_limit_deg", 0.0, 0.0, 45.0))
	var down := deg_to_rad(_finite_number(settings, "down_limit_deg", 0.0, 0.0, 45.0))
	var response := _finite_number(profile, "response", 12.0, 0.0, 60.0)
	var step := maxf(delta, 0.0) if is_finite(delta) else 0.0
	var target := clampf(pitch * gain, -down, up)
	smoothed_pitch = lerpf(smoothed_pitch, target, 1.0 - exp(-response * step))
	# A stance switch immediately respects the new stance's smaller safe range.
	smoothed_pitch = clampf(smoothed_pitch, -down, up)
	var chest_index := int(layer.bone_indices.get(&"spine2", -1))
	if chest_index < 0 or not aim_world.is_finite():
		return
	var chest_world: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(chest_index).origin
	var forward := aim_world - chest_world
	forward.y = 0.0
	if forward.length_squared() < 0.000001:
		return
	# Bone local X is not the character's pitch axis after retargeting/prone.
	var right := (skeleton.global_basis.inverse() * forward.normalized().cross(Vector3.UP)).normalized()
	var protected := {}
	for name: StringName in [&"hips", &"left_foot", &"right_foot"]:
		var index := int(layer.bone_indices.get(name, -1))
		if index >= 0: protected[index] = skeleton.get_bone_global_pose(index)
	var seen := {}
	for part in CHAIN.size():
		var index := int(layer.bone_indices.get(CHAIN[part], -1))
		if index < 0 or seen.has(index): continue
		seen[index] = true
		var before := skeleton.get_bone_pose_rotation(index)
		layer._apply_skeleton_space_rotation(index, Quaternion(right, smoothed_pitch * WEIGHTS[part]))
		var after := skeleton.get_bone_pose_rotation(index)
		applied[index] = {"before": before, "after": after}
		last_spine_delta += before.angle_to(after)
		last_bone_count += 1
	for index: int in protected:
		var before: Transform3D = protected[index]
		var after := skeleton.get_bone_global_pose(index)
		last_protected_delta = maxf(last_protected_delta, before.origin.distance_to(after.origin))
		for axis in 3:
			last_protected_delta = maxf(last_protected_delta, before.basis[axis].distance_to(after.basis[axis]))
	last_pitch_rad = smoothed_pitch
	last_reason = "applied"


func _finite_number(row: Dictionary, key: String, fallback: float, low: float, high: float) -> float:
	var value: Variant = row.get(key, fallback)
	if not value is float and not value is int: return fallback
	return clampf(float(value), low, high) if is_finite(float(value)) else fallback
