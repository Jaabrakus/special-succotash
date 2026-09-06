extends RefCounted

## Visual envelope only. The existing socket solver remains the bone writer.
const PROFILE := "res://config/fire_recoil_presentation.json"
var attack := 0.035
var release := 0.18
var flare := 5.0
var prone_scale := 0.35
var age := 1.0
var start_weight := 0.0

func _init() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE))
	if data is Dictionary:
		attack = clampf(float(data.get("attack_seconds", attack)), 0.015, 0.08)
		release = clampf(float(data.get("return_seconds", release)), 0.08, 0.30)
		flare = clampf(float(data.get("right_elbow_swivel_degrees", flare)), 0.0, 8.0)
		prone_scale = clampf(float(data.get("prone_scale", prone_scale)), 0.0, 1.0)

func trigger() -> void:
	# Retrigger from the current envelope: no abrupt reset or additive runaway.
	start_weight = weight()
	age = 0.0

func advance(delta: float) -> void:
	age = minf(age + maxf(delta, 0.0), 1.0)

func weight() -> float:
	if age < attack:
		return lerpf(start_weight, 1.0, smoothstep(0.0, attack, age))
	return 1.0 - smoothstep(attack, attack + release, age)

func offset(posture: StringName) -> float:
	return deg_to_rad(flare) * weight() * (prone_scale if posture == &"PRONE" else 1.0)

func apply_elbow(pose: Node3D, posture: StringName) -> void:
	var angle := offset(posture)
	if angle < 0.00001 or pose.skeleton == null:
		return
	var skeleton: Skeleton3D = pose.skeleton
	var arm: int = pose.bone_indices.get(&"mixamorig_RightArm", -1)
	var elbow: int = pose.bone_indices.get(&"mixamorig_RightForeArm", -1)
	var hand: int = pose.bone_indices.get(&"mixamorig_RightHand", -1)
	var left: int = pose.bone_indices.get(&"mixamorig_LeftArm", -1)
	if mini(mini(arm, elbow), mini(hand, left)) < 0:
		return
	# All four transforms use skeleton-global space, not world space. Rotate the
	# arm plane around its fixed endpoints, then preserve the final wrist pose.
	var upper := skeleton.get_bone_global_pose(arm)
	var fore := skeleton.get_bone_global_pose(elbow)
	var wrist := skeleton.get_bone_global_pose(hand)
	var axis := (wrist.origin - upper.origin).normalized()
	var outward := upper.origin - skeleton.get_bone_global_pose(left).origin
	if axis.cross(fore.origin - upper.origin).dot(outward) < 0.0:
		angle = -angle
	var rotation := Basis(axis, angle)
	fore.origin = upper.origin + rotation * (fore.origin - upper.origin)
	fore.basis = rotation * fore.basis
	upper.basis = rotation * upper.basis
	skeleton.set_bone_global_pose_override(arm, upper, 1.0, true)
	skeleton.set_bone_global_pose_override(elbow, fore, 1.0, true)
	skeleton.set_bone_global_pose_override(hand, wrist, 1.0, true)
	skeleton.force_update_all_bone_transforms()
