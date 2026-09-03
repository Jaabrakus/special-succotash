class_name SocomOperatorFootContactLock
extends Node3D

## Presentation-only stair contact owner.
##
## Two RayCast3D probes convert terrain height into foot targets. One final
## SkeletonModifier3D consumes those targets and writes only the six leg bones.
## CharacterBody3D remains the sole movement and collision owner.

const GroundingProfile := preload(
	"res://scripts/player/operator_foot_grounding_profile.gd"
)
const GroundingModifier := preload(
	"res://scripts/player/operator_foot_grounding_modifier.gd"
)

const LEFT_FOOT := &"mixamorig_LeftFoot"
const RIGHT_FOOT := &"mixamorig_RightFoot"

var skeleton: Skeleton3D
var authority_body: CharacterBody3D
var left_target: Marker3D
var right_target: Marker3D
var left_ground_ray: RayCast3D
var right_ground_ray: RayCast3D
var grounding_modifier: SocomOperatorFootGroundingModifier
var bone_indices: Dictionary = {}
var profile: Dictionary = {}

var grounding_enabled: bool = true
var collision_mask: int = 1
var ray_start_height_m: float = 0.42
var ray_depth_m: float = 0.72
var maximum_step_up_m: float = 0.28
var maximum_step_down_m: float = 0.18
var maximum_slope_cos: float = cos(deg_to_rad(48.0))
var target_response_mps: float = 2.8
var weight_response_per_second: float = 14.0

var left_offset_m: float = 0.0
var right_offset_m: float = 0.0
var left_weight: float = 0.0
var right_weight: float = 0.0
var left_ray_hit: bool = false
var right_ray_hit: bool = false
var protected_pose_active: bool = false
var last_body_translation_delta_m: float = 0.0
var last_body_velocity_delta_mps: float = 0.0


func bind(
	target_skeleton: Skeleton3D,
	target_body: CharacterBody3D,
	contract: SocomOperatorIKContract
) -> void:
	skeleton = target_skeleton
	authority_body = target_body
	if skeleton == null or authority_body == null or contract == null:
		return
	profile = GroundingProfile.load_profile()
	_configure(profile)
	bone_indices[LEFT_FOOT] = skeleton.find_bone(LEFT_FOOT)
	bone_indices[RIGHT_FOOT] = skeleton.find_bone(RIGHT_FOOT)
	left_target = contract.left_foot_target
	right_target = contract.right_foot_target
	left_ground_ray = _new_ground_ray("LeftFootGroundRay")
	right_ground_ray = _new_ground_ray("RightFootGroundRay")
	grounding_modifier = skeleton.get_node_or_null(
		"OperatorFootGroundingModifier"
	) as SocomOperatorFootGroundingModifier
	if grounding_modifier == null:
		grounding_modifier = GroundingModifier.new()
		grounding_modifier.name = "OperatorFootGroundingModifier"
		skeleton.add_child(grounding_modifier)
	grounding_modifier.bind(skeleton, profile)


func apply(
	_direction: Vector2,
	_speed_normalized: float,
	posture: StringName,
	movement_state: StringName,
	action: StringName,
	delta: float,
	protect_authored_pose: bool = false
) -> void:
	if not _ready_to_sample():
		return
	var body_transform_before := authority_body.global_transform
	var body_velocity_before := authority_body.velocity
	protected_pose_active = protect_authored_pose or action != &""
	var eligible := (
		grounding_enabled
		and not protected_pose_active
		and posture in [&"STANDING", &"CROUCHED"]
		and movement_state in [&"STANDING", &"CROUCHED", &"LOCOMOTION"]
		and authority_body.is_on_floor()
	)
	if not eligible:
		_deactivate_immediately()
		_measure_body_invariance(body_transform_before, body_velocity_before)
		return

	var left_foot_world := _bone_world_transform(LEFT_FOOT)
	var right_foot_world := _bone_world_transform(RIGHT_FOOT)
	var left_sample := _sample_ground(left_ground_ray, left_foot_world.origin)
	var right_sample := _sample_ground(right_ground_ray, right_foot_world.origin)
	left_ray_hit = bool(left_sample.get("valid", false))
	right_ray_hit = bool(right_sample.get("valid", false))
	left_offset_m = _approach_offset(
		left_offset_m,
		float(left_sample.get("offset_m", 0.0)) if left_ray_hit else 0.0,
		delta
	)
	right_offset_m = _approach_offset(
		right_offset_m,
		float(right_sample.get("offset_m", 0.0)) if right_ray_hit else 0.0,
		delta
	)
	left_weight = _approach_weight(left_weight, 1.0 if left_ray_hit else 0.0, delta)
	right_weight = _approach_weight(right_weight, 1.0 if right_ray_hit else 0.0, delta)
	var left_world_target := left_foot_world.origin + Vector3.UP * left_offset_m
	var right_world_target := right_foot_world.origin + Vector3.UP * right_offset_m
	left_target.global_position = left_world_target
	right_target.global_position = right_world_target
	grounding_modifier.set_ground_targets(
		left_world_target, right_world_target, left_weight, right_weight
	)
	_measure_body_invariance(body_transform_before, body_velocity_before)


func get_debug_state() -> Dictionary:
	var modifier_state := (
		grounding_modifier.get_debug_state()
		if grounding_modifier != null else {}
	)
	return {
		"active": bool(modifier_state.get("active", false)),
		"side": _dominant_side(),
		"weight": maxf(left_weight, right_weight),
		"world_slip_cm": maxf(
			float(modifier_state.get("left_error_m", 0.0)),
			float(modifier_state.get("right_error_m", 0.0))
		) * 100.0,
		"ray_count": 2,
		"left_ray_hit": left_ray_hit,
		"right_ray_hit": right_ray_hit,
		"left_offset_m": left_offset_m,
		"right_offset_m": right_offset_m,
		"protected_pose_active": protected_pose_active,
		"body_translation_delta_m": last_body_translation_delta_m,
		"body_velocity_delta_mps": last_body_velocity_delta_mps,
		"skeleton_process_priority": skeleton.process_priority if skeleton != null else 0,
		"modifier": modifier_state,
	}


func set_invariance_probe_enabled(enabled: bool) -> void:
	if grounding_modifier != null:
		grounding_modifier.set_invariance_probe_enabled(enabled)


func set_collision_mask_for_test(mask: int) -> void:
	collision_mask = mask
	for ray in [left_ground_ray, right_ground_ray]:
		if ray != null:
			ray.collision_mask = collision_mask


func _configure(source: Dictionary) -> void:
	grounding_enabled = bool(source.get("enabled", true))
	collision_mask = maxi(int(source.get("collision_mask", 1)), 1)
	ray_start_height_m = clampf(
		float(source.get("ray_start_height_m", 0.42)), 0.10, 0.80
	)
	ray_depth_m = clampf(float(source.get("ray_depth_m", 0.72)), 0.20, 1.20)
	maximum_step_up_m = clampf(
		float(source.get("maximum_step_up_m", 0.28)), 0.02, 0.45
	)
	maximum_step_down_m = clampf(
		float(source.get("maximum_step_down_m", 0.18)), 0.02, 0.40
	)
	maximum_slope_cos = cos(deg_to_rad(clampf(
		float(source.get("maximum_slope_deg", 48.0)), 1.0, 65.0
	)))
	target_response_mps = clampf(
		float(source.get("target_response_mps", 2.8)), 0.10, 8.0
	)
	weight_response_per_second = clampf(
		float(source.get("weight_response_per_second", 14.0)), 1.0, 40.0
	)


func _sample_ground(ray: RayCast3D, foot_world: Vector3) -> Dictionary:
	if ray == null:
		return {"valid": false}
	ray.global_transform = Transform3D(
		Basis.IDENTITY,
		foot_world + Vector3.UP * ray_start_height_m
	)
	ray.target_position = Vector3.DOWN * (ray_start_height_m + ray_depth_m)
	ray.force_raycast_update()
	if not ray.is_colliding():
		return {"valid": false}
	var normal := ray.get_collision_normal().normalized()
	if normal.dot(Vector3.UP) < maximum_slope_cos:
		return {"valid": false}
	var offset := ray.get_collision_point().y - authority_body.global_position.y
	if offset < -maximum_step_down_m or offset > maximum_step_up_m:
		return {"valid": false}
	return {
		"valid": true,
		"offset_m": offset,
		"point": ray.get_collision_point(),
		"normal": normal,
	}


func _approach_offset(current: float, target: float, delta: float) -> float:
	return move_toward(
		current,
		target,
		target_response_mps * clampf(delta, 0.0, 1.0 / 20.0)
	)


func _approach_weight(current: float, target: float, delta: float) -> float:
	return move_toward(
		current,
		target,
		weight_response_per_second * clampf(delta, 0.0, 1.0 / 20.0)
	)


func _deactivate_immediately() -> void:
	left_weight = 0.0
	right_weight = 0.0
	left_offset_m = 0.0
	right_offset_m = 0.0
	left_ray_hit = false
	right_ray_hit = false
	if grounding_modifier != null:
		grounding_modifier.clear_targets()


func _measure_body_invariance(
	before_transform: Transform3D,
	before_velocity: Vector3
) -> void:
	last_body_translation_delta_m = before_transform.origin.distance_to(
		authority_body.global_transform.origin
	)
	last_body_velocity_delta_mps = before_velocity.distance_to(authority_body.velocity)


func _dominant_side() -> StringName:
	if maxf(left_weight, right_weight) <= 0.001:
		return &""
	return &"LEFT" if absf(left_offset_m) >= absf(right_offset_m) else &"RIGHT"


func _ready_to_sample() -> bool:
	return (
		skeleton != null
		and authority_body != null
		and left_target != null
		and right_target != null
		and left_ground_ray != null
		and right_ground_ray != null
		and grounding_modifier != null
		and int(bone_indices.get(LEFT_FOOT, -1)) >= 0
		and int(bone_indices.get(RIGHT_FOOT, -1)) >= 0
	)


func _bone_world_transform(bone_name: StringName) -> Transform3D:
	var bone_index := int(bone_indices.get(bone_name, -1))
	if bone_index < 0:
		return Transform3D.IDENTITY
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)


func _new_ground_ray(ray_name: String) -> RayCast3D:
	var ray := RayCast3D.new()
	ray.name = ray_name
	ray.enabled = false
	ray.collide_with_bodies = true
	ray.collide_with_areas = false
	ray.collision_mask = collision_mask
	ray.exclude_parent = false
	add_child(ray)
	ray.add_exception(authority_body)
	return ray
