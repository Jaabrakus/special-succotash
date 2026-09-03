extends SceneTree

## Rendered-bone proof for the shared ordinary-ready and accepted-shot recovery
## contract. Idle and moving drivers advance in the same frame so their clean
## posture-matched upper-body poses are sampled at the same playhead time.

const DriverScript := preload(
	"res://scripts/player/operator_animation_driver.gd"
)

const SILHOUETTE_BONES: Array[StringName] = [
	&"mixamorig_Spine",
	&"mixamorig_Spine1",
	&"mixamorig_Spine2",
	&"mixamorig_Neck",
	&"mixamorig_Head",
	&"mixamorig_LeftShoulder",
	&"mixamorig_LeftArm",
	&"mixamorig_LeftForeArm",
	&"mixamorig_LeftHand",
	&"mixamorig_RightShoulder",
	&"mixamorig_RightArm",
	&"mixamorig_RightForeArm",
	&"mixamorig_RightHand",
]

const MAX_ROTATION_DELTA_DEG := 3.25
const MAX_SPINE_RELATIVE_POSITION_DELTA_CM := 3.0

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_posture(
		&"STANDING",
		Vector2.UP,
		&"LOCOMOTION",
		&"FULL",
		5.45
	)
	await _check_posture(
		&"CROUCHED",
		Vector2.UP,
		&"LOCOMOTION",
		&"WALK",
		2.60
	)
	_finish()


func _check_posture(
	posture: StringName,
	direction: Vector2,
	movement_state: StringName,
	gait: StringName,
	speed_mps: float
) -> void:
	var idle_driver = DriverScript.new()
	var moving_driver = DriverScript.new()
	root.add_child(idle_driver)
	root.add_child(moving_driver)
	await process_frame
	await process_frame
	idle_driver.animation_profile.transitions["enabled"] = false
	moving_driver.animation_profile.transitions["enabled"] = false
	idle_driver.clear_fire_ready_aim()
	moving_driver.clear_fire_ready_aim()
	idle_driver.set_visual_inputs(
		Vector2.ZERO,
		posture,
		deg_to_rad(12.0),
		deg_to_rad(-4.0),
		1.0,
		false,
		0.0,
		0.0,
		posture,
		0.0,
		gait,
		0.0
	)
	moving_driver.set_visual_inputs(
		direction,
		posture,
		deg_to_rad(12.0),
		deg_to_rad(-4.0),
		1.0,
		false,
		0.0,
		1.0,
		movement_state,
		0.0,
		gait,
		speed_mps
	)
	for _frame in range(36):
		await process_frame
	var idle_ready_debug: Dictionary = idle_driver.get_animation_debug_state()
	var moving_ready_debug: Dictionary = moving_driver.get_animation_debug_state()
	_expect(
		float(idle_ready_debug.get("clean_ready_pose_weight", 0.0)) >= 0.98
		and float(moving_ready_debug.get("clean_ready_pose_weight", 0.0)) >= 0.98,
		"%s stationary and moving ordinary Ready Aim select the clean shared pose" % posture
	)
	_compare_upper_body(posture, "ordinary_ready", idle_driver, moving_driver)
	_expect(idle_driver.notify_fired(), "%s stationary accepted shot starts recovery" % posture)
	_expect(moving_driver.notify_fired(), "%s moving accepted shot starts recovery" % posture)
	for _frame in range(36):
		await process_frame
	var idle_debug: Dictionary = idle_driver.get_animation_debug_state()
	var moving_debug: Dictionary = moving_driver.get_animation_debug_state()
	var idle_latch: Dictionary = idle_debug.get("fire_upper_body_latch", {})
	var moving_latch: Dictionary = moving_debug.get("fire_upper_body_latch", {})
	_expect(
		StringName(idle_latch.get("owner_state", &"")) == &"FIRE_RECOVERY"
		and StringName(moving_latch.get("owner_state", &"")) == &"FIRE_RECOVERY",
		"%s comparison remains inside the bounded recovery window" % posture
	)
	_compare_upper_body(posture, "fire_recovery", idle_driver, moving_driver)
	idle_driver.queue_free()
	moving_driver.queue_free()
	await process_frame


func _compare_upper_body(
	posture: StringName,
	phase: String,
	idle_driver: Node,
	moving_driver: Node
) -> void:
	var idle_spine_index: int = idle_driver.skeleton.find_bone(&"mixamorig_Spine")
	var moving_spine_index: int = moving_driver.skeleton.find_bone(&"mixamorig_Spine")
	var idle_spine_origin: Vector3 = idle_driver.skeleton.get_bone_global_pose(
		idle_spine_index
	).origin
	var moving_spine_origin: Vector3 = moving_driver.skeleton.get_bone_global_pose(
		moving_spine_index
	).origin
	var maximum_rotation_delta_deg := 0.0
	var maximum_rotation_bone := &""
	var maximum_position_delta_cm := 0.0
	var maximum_position_bone := &""
	for bone_name: StringName in SILHOUETTE_BONES:
		var idle_index: int = idle_driver.skeleton.find_bone(bone_name)
		var moving_index: int = moving_driver.skeleton.find_bone(bone_name)
		_expect(
			idle_index >= 0 and moving_index >= 0,
			"%s %s comparison resolves bone %s" % [posture, phase, bone_name]
		)
		if idle_index < 0 or moving_index < 0:
			continue
		var idle_pose: Transform3D = idle_driver.skeleton.get_bone_global_pose(
			idle_index
		)
		var moving_pose: Transform3D = moving_driver.skeleton.get_bone_global_pose(
			moving_index
		)
		var rotation_delta_deg := rad_to_deg(
			idle_pose.basis.get_rotation_quaternion().angle_to(
				moving_pose.basis.get_rotation_quaternion()
			)
		)
		var position_delta_cm := (
			(idle_pose.origin - idle_spine_origin)
			- (moving_pose.origin - moving_spine_origin)
		).length() * 100.0
		if rotation_delta_deg > maximum_rotation_delta_deg:
			maximum_rotation_delta_deg = rotation_delta_deg
			maximum_rotation_bone = bone_name
		if position_delta_cm > maximum_position_delta_cm:
			maximum_position_delta_cm = position_delta_cm
			maximum_position_bone = bone_name
	print(
		"FIRE_RECOVERY_AIM_PARITY_METRIC posture=%s phase=%s max_rotation_delta_deg=%.3f rotation_bone=%s max_spine_relative_position_delta_cm=%.3f position_bone=%s" % [
			posture,
			phase,
			maximum_rotation_delta_deg,
			maximum_rotation_bone,
			maximum_position_delta_cm,
			maximum_position_bone,
		]
	)
	_expect(
		maximum_rotation_delta_deg <= MAX_ROTATION_DELTA_DEG,
		"%s moving %s keeps stationary Spine-to-Head and rifle-limb rotations" % [posture, phase]
	)
	_expect(
		maximum_position_delta_cm <= MAX_SPINE_RELATIVE_POSITION_DELTA_CM,
		"%s moving %s keeps the stationary upper-body silhouette" % [posture, phase]
	)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("FIRE_RECOVERY_AIM_PARITY_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("FIRE_RECOVERY_AIM_PARITY_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("FIRE_RECOVERY_AIM_PARITY_REGRESSION PASS")
		quit(0)
	else:
		print("FIRE_RECOVERY_AIM_PARITY_REGRESSION FAIL %s" % [failures])
		quit(1)
