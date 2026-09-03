extends "res://scripts/player/operator_animation_driver_state.gd"

## Stable visual-input, tuning, clip-query, and player-access API.

const PoseOwnershipContract := preload(
	"res://scripts/player/weapon_ownership_contract.gd"
)

func set_visual_inputs(
	direction: Vector2,
	posture_name: StringName,
	aim_yaw: float,
	aim_pitch: float,
	ready_weight: float,
	is_firing: bool,
	obstruction: float,
	speed_normalized: float = -1.0,
	state_name: StringName = &"LOCOMOTION",
	vertical_velocity: float = 0.0,
	gait_name: StringName = &"WALK",
	actual_speed_mps: float = -1.0,
	world_aim_target: Vector3 = Vector3.ZERO,
	desired_direction: Vector2 = Vector2.ZERO,
	desired_strength: float = -1.0,
	response_mode: StringName = &"IDLE",
	peek: float = 0.0
) -> void:
	_explicit_visual_inputs = true
	movement_direction = direction
	movement_speed_normalized = clampf(speed_normalized if speed_normalized >= 0.0 else direction.length(), 0.0, 1.0)
	movement_gait = &"FULL" if gait_name == &"FULL" else &"WALK"
	movement_speed_mps = actual_speed_mps if actual_speed_mps >= 0.0 else movement_speed_normalized * float(animation_profile.locomotion["full_nominal_speed_mps"])
	posture = posture_name
	aim_yaw_rad = aim_yaw
	aim_pitch_rad = aim_pitch
	requested_weapon_ready_weight = clampf(ready_weight, 0.0, 1.0)
	firing = is_firing
	obstruction_amount = clampf(obstruction, 0.0, 1.0)
	movement_state = state_name
	vertical_speed = vertical_velocity
	visual_aim_target = world_aim_target
	movement_intent_direction = desired_direction
	movement_intent_strength = clampf(
		desired_strength if desired_strength >= 0.0 else desired_direction.length(),
		0.0,
		1.0
	)
	movement_response_mode = response_mode
	peek_amount = clampf(peek, -1.0, 1.0)


func _trigger_fire_ready_aim() -> void:
	var ready_profile: Variant = equipped_weapon_handling_profile.get("ready_aim", {})
	var hold_seconds := fire_ready_hold_seconds
	if ready_profile is Dictionary:
		hold_seconds = float(
			(ready_profile as Dictionary).get("fire_hold_seconds", hold_seconds)
		)
	if fire_upper_body_latch != null:
		fire_upper_body_latch.configure(hold_seconds)
		fire_upper_body_latch.notify_accepted_shot()
		_fire_ready_hold_remaining = (
			fire_upper_body_latch.grace_remaining_seconds
		)
	else:
		_fire_ready_hold_remaining = maxf(hold_seconds, 0.0)
	# Let the normal bounded ready response raise the weapon. A one-frame jump to
	# full ownership makes the socket IK replace the current arm chain before the
	# stance/fire animation has blended, which visibly folds the elbows.


func _update_weapon_ready(delta: float, reload_active: bool = false) -> void:
	if fire_upper_body_latch != null:
		fire_upper_body_latch.set_context(posture, reload_active)
		# Preserve compatibility with focused tools that seed the old diagnostic
		# scalar directly while the latch becomes the canonical live owner.
		if (
			_fire_ready_hold_remaining
			> fire_upper_body_latch.grace_remaining_seconds
		):
			fire_upper_body_latch.set_grace_remaining(
				_fire_ready_hold_remaining
			)
		fire_upper_body_latch.advance(delta, reload_active)
		_fire_ready_hold_remaining = (
			fire_upper_body_latch.grace_remaining_seconds
		)
	else:
		_fire_ready_hold_remaining = maxf(
			_fire_ready_hold_remaining - maxf(delta, 0.0),
			0.0
		)
	var ready_target := maxf(
		requested_weapon_ready_weight,
		1.0 if _fire_upper_body_selected() else 0.0
	)
	var response := (
		ready_enter_response
		if ready_target > weapon_ready_weight
		else ready_exit_response
	)
	weapon_ready_weight = PoseOwnershipContract.bounded_ready_weight(
		weapon_ready_weight,
		ready_target,
		response,
		delta
	)
	if ready_target <= 0.0 and weapon_ready_weight <= 0.001:
		weapon_ready_weight = 0.0


func clear_fire_ready_aim() -> void:
	_fire_ready_hold_remaining = 0.0
	if fire_upper_body_latch != null:
		fire_upper_body_latch.clear()
	if requested_weapon_ready_weight <= 0.0:
		weapon_ready_weight = 0.0


func _fire_upper_body_selected() -> bool:
	if fire_upper_body_latch != null:
		return fire_upper_body_latch.is_selected()
	return _fire_ready_hold_remaining > 0.0


func set_pose_preview_paused(paused: bool) -> void:
	if animation_player != null:
		animation_player.speed_scale = 0.0 if paused else 1.0


func set_procedural_pose_rotation(
	posture_name: StringName,
	bone_name: StringName,
	rotation_degrees: Vector3
) -> void:
	if posture_layer != null:
		posture_layer.set_procedural_rotation_degrees(
			posture_name,
			bone_name,
			rotation_degrees
		)


func get_procedural_pose_rotation(
	posture_name: StringName,
	bone_name: StringName
) -> Vector3:
	return (
		posture_layer.get_procedural_rotation_degrees(posture_name, bone_name)
		if posture_layer != null
		else Vector3.ZERO
	)


func save_procedural_pose_profile() -> bool:
	return posture_layer != null and posture_layer.save_procedural_profile()


func reload_procedural_pose_profile() -> bool:
	return posture_layer != null and posture_layer.reload_procedural_profile()



func get_clip_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for clip_name in available_clips.keys():
		names.append(clip_name as StringName)
	names.sort()
	return names


func has_clip(clip_name: StringName) -> bool:
	return available_clips.has(clip_name)


func get_source_animation_name(clip_name: StringName) -> StringName:
	return asset_runtime.get_source_animation_name(clip_name) if asset_runtime != null else &""


func _get_player() -> CharacterBody3D:
	var node: Node = get_parent()
	while node != null:
		if node is CharacterBody3D:
			return node as CharacterBody3D
		node = node.get_parent()
	return null
