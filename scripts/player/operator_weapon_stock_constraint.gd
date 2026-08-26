class_name SocomOperatorWeaponStockConstraint
extends Node3D

## Visual-only shoulder-pocket constraint for a shouldered weapon. The camera
## still owns aim and the server still owns the shot. This component only keeps
## the rendered buttstock on the operator before both hands solve to the rifle.

var skeleton: Skeleton3D
var stock_socket: Marker3D
var pocket_marker: Marker3D
var enabled: bool = false
var inward_offset_m: float = 0.055
var downward_offset_m: float = 0.035
var forward_offset_m: float = 0.015
var maximum_correction_m: float = 0.40
var last_contact_error_m: float = INF
var last_correction_m: float = 0.0


func _ready() -> void:
	_ensure_pocket_marker()


func bind(target_skeleton: Skeleton3D, target_stock_socket: Marker3D) -> void:
	skeleton = target_skeleton
	stock_socket = target_stock_socket
	_ensure_pocket_marker()


func configure(raw_profile: Variant) -> void:
	if not raw_profile is Dictionary:
		enabled = false
		return
	var profile := raw_profile as Dictionary
	enabled = bool(profile.get("enabled", false))
	inward_offset_m = clampf(float(profile.get("inward_offset_m", inward_offset_m)), 0.0, 0.15)
	downward_offset_m = clampf(
		float(profile.get("downward_offset_m", downward_offset_m)),
		-0.10,
		0.15
	)
	forward_offset_m = clampf(float(profile.get("forward_offset_m", forward_offset_m)), -0.10, 0.15)
	maximum_correction_m = clampf(
		float(profile.get("maximum_correction_m", maximum_correction_m)),
		0.05,
		0.60
	)


func is_active() -> bool:
	return enabled and skeleton != null and stock_socket != null


func correction_for(aim_direction: Vector3) -> Vector3:
	if not is_active():
		last_contact_error_m = INF
		last_correction_m = 0.0
		return Vector3.ZERO
	var right_index := _bone_index(["mixamorig_RightArm", "Bip01 R UpperArm"])
	var left_index := _bone_index(["mixamorig_LeftArm", "Bip01 L UpperArm"])
	if right_index < 0 or left_index < 0:
		last_contact_error_m = INF
		last_correction_m = 0.0
		return Vector3.ZERO
	var right_shoulder := skeleton.global_transform * skeleton.get_bone_global_pose(right_index).origin
	var left_shoulder := skeleton.global_transform * skeleton.get_bone_global_pose(left_index).origin
	var inward := left_shoulder - right_shoulder
	if inward.length_squared() < 0.000001:
		inward = -skeleton.global_basis.x
	inward = inward.normalized()
	var forward := aim_direction.normalized()
	if forward.length_squared() < 0.50:
		forward = (-skeleton.global_basis.z).normalized()
	var pocket := (
		right_shoulder
		+ inward * inward_offset_m
		- Vector3.UP * downward_offset_m
		+ forward * forward_offset_m
	)
	pocket_marker.global_position = pocket
	var correction := pocket - stock_socket.global_position
	last_contact_error_m = correction.length()
	if correction.length() > maximum_correction_m:
		correction = correction.normalized() * maximum_correction_m
	last_correction_m = correction.length()
	return correction


func measure_contact_error() -> float:
	if not is_active() or pocket_marker == null:
		return INF
	last_contact_error_m = pocket_marker.global_position.distance_to(
		stock_socket.global_position
	)
	return last_contact_error_m


func get_debug_state() -> Dictionary:
	return {
		"active": is_active(),
		"socket": stock_socket.name if stock_socket != null else &"",
		"pocket_world_position": (
			pocket_marker.global_position if pocket_marker != null else Vector3.ZERO
		),
		"stock_world_position": (
			stock_socket.global_position if stock_socket != null else Vector3.ZERO
		),
		"contact_error_m": last_contact_error_m,
		"correction_m": last_correction_m,
	}


func _ensure_pocket_marker() -> void:
	if pocket_marker != null:
		return
	pocket_marker = Marker3D.new()
	pocket_marker.name = "RightShoulderPocket"
	add_child(pocket_marker)


func _bone_index(candidates: Array[String]) -> int:
	for bone_name in candidates:
		var index := skeleton.find_bone(bone_name)
		if index >= 0:
			return index
	return -1
