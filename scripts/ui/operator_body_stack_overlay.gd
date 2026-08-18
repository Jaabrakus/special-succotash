class_name SocomOperatorBodyStackOverlay
extends Control

## Screen-space projection of the operator's real animated spine against a
## world-vertical plumb line. This is diagnostic only and never changes pose.

const STACK_BONES: Array[StringName] = [
	&"mixamorig_Hips",
	&"mixamorig_Spine",
	&"mixamorig_Spine1",
	&"mixamorig_Spine2",
	&"mixamorig_Neck",
	&"mixamorig_Head",
]

const ARM_CHAINS: Array[Array] = [
	[&"mixamorig_LeftShoulder", &"mixamorig_LeftArm", &"mixamorig_LeftForeArm", &"mixamorig_LeftHand"],
	[&"mixamorig_RightShoulder", &"mixamorig_RightArm", &"mixamorig_RightForeArm", &"mixamorig_RightHand"],
]

const LEG_CHAINS: Array[Array] = [
	[&"mixamorig_Hips", &"mixamorig_LeftUpLeg", &"mixamorig_LeftLeg", &"mixamorig_LeftFoot"],
	[&"mixamorig_Hips", &"mixamorig_RightUpLeg", &"mixamorig_RightLeg", &"mixamorig_RightFoot"],
]

const TRAIL_BONES: Array[StringName] = [
	&"mixamorig_LeftHand", &"mixamorig_RightHand",
	&"mixamorig_LeftFoot", &"mixamorig_RightFoot",
]

const TRAIL_FRAMES := 8

var driver
var camera: Camera3D
var subject: Node3D
var joint_trails: Dictionary = {}


func configure(animation_driver, gameplay_camera: Camera3D, player_subject: Node3D) -> void:
	driver = animation_driver
	camera = gameplay_camera
	subject = player_subject
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if visible:
		_sample_joint_trails()
	else:
		joint_trails.clear()
	queue_redraw()


func _draw() -> void:
	if not visible or driver == null or camera == null:
		return
	var skeleton: Skeleton3D = driver.get("skeleton")
	if skeleton == null:
		return
	var world_points: Array[Vector3] = []
	for bone_name in STACK_BONES:
		var bone_index := skeleton.find_bone(bone_name)
		if bone_index < 0:
			return
		world_points.append(
			skeleton.global_transform * skeleton.get_bone_global_pose(bone_index).origin
		)
	for point in world_points:
		if camera.is_position_behind(point):
			return

	var hip := world_points[0]
	var posture := StringName(driver.get("posture"))
	var gameplay_state := StringName(driver.get("movement_state"))
	var stance_axis := Vector3.UP
	var axis_name := "vertical"
	if posture == &"PRONE" or gameplay_state in [&"DIVING", &"ROLLING"]:
		stance_axis = -subject.global_basis.z.normalized() if subject != null else Vector3.FORWARD
		axis_name = "forward"
	var plumb_world: Array[Vector3] = []
	for point in world_points:
		if axis_name == "vertical":
			plumb_world.append(Vector3(hip.x, point.y, hip.z))
		else:
			plumb_world.append(hip + stance_axis * point.distance_to(hip))
	var stack_screen := PackedVector2Array()
	var plumb_screen := PackedVector2Array()
	for index in range(world_points.size()):
		stack_screen.append(camera.unproject_position(world_points[index]))
		plumb_screen.append(camera.unproject_position(plumb_world[index]))

	var green := Color(0.28, 1.0, 0.34, 0.95)
	var cyan := Color(0.15, 0.90, 1.0, 0.98)
	var orange := Color(1.0, 0.58, 0.12, 0.90)
	var arm_color := Color(0.14, 0.92, 1.0, 0.96)
	var leg_color := Color(0.08, 0.76, 1.0, 0.96)
	draw_line(plumb_screen[0], plumb_screen[-1], green, 3.0, true)
	draw_polyline(stack_screen, cyan, 4.0, true)
	for index in range(stack_screen.size()):
		draw_line(plumb_screen[index], stack_screen[index], orange, 1.5, true)
		draw_circle(plumb_screen[index], 4.0, green)
		draw_circle(stack_screen[index], 5.0, cyan)

	_draw_joint_chains(skeleton, ARM_CHAINS, arm_color)
	_draw_joint_chains(skeleton, LEG_CHAINS, leg_color)
	_draw_weapon_pose(skeleton)
	_draw_joint_trails()

	var head_offset := world_points[-1] - hip
	var chest_offset := world_points[3] - hip
	var lean_degrees := rad_to_deg(head_offset.normalized().angle_to(stance_axis))
	var right := Vector3.RIGHT
	var backward := Vector3.BACK
	if subject != null:
		right = subject.global_basis.x.normalized()
		backward = subject.global_basis.z.normalized()
	var head_back_cm := head_offset.dot(backward) * 100.0
	var head_side_cm := head_offset.dot(right) * 100.0
	var chest_back_cm := chest_offset.dot(backward) * 100.0

	var legend_position := stack_screen[-1] + Vector2(18.0, -12.0)
	draw_string(
		ThemeDB.fallback_font,
		legend_position,
		"BODY RIG  %s  axis error %.1f deg  back %+.1f cm  side %+.1f cm"
		% [posture, lean_degrees, head_back_cm, head_side_cm],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		13,
		Color.WHITE
	)
	var weapon_solver = driver.get("weapon_pose_solver")
	if weapon_solver != null:
		var weapon_state: Dictionary = weapon_solver.get_debug_state()
		draw_string(
			ThemeDB.fallback_font,
			legend_position + Vector2(0.0, 34.0),
			"weapon IK  trigger %.1f cm  support %.1f cm  aim %.2f deg  elbows %.0f/%.0f"
			% [
				float(weapon_state.get("trigger_hand_error_m", 0.0)) * 100.0,
				float(weapon_state.get("support_hand_error_m", 0.0)) * 100.0,
				float(weapon_state.get("weapon_aim_error_deg", 0.0)),
				float(weapon_state.get("right_elbow_angle_deg", 0.0)),
				float(weapon_state.get("left_elbow_angle_deg", 0.0)),
			],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			13,
			Color(1.0, 0.82, 0.25, 1.0)
		)
	draw_string(
		ThemeDB.fallback_font,
		legend_position + Vector2(0.0, 17.0),
		"chest back %+.1f cm  green=%s reference  cyan=animated spine + limbs  [K hide]"
		% [chest_back_cm, axis_name],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		13,
		Color.WHITE
	)


func _sample_joint_trails() -> void:
	if driver == null:
		return
	var skeleton: Skeleton3D = driver.get("skeleton")
	if skeleton == null:
		return
	for bone_name in TRAIL_BONES:
		var bone_index := skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var point: Vector3 = (
			skeleton.global_transform * skeleton.get_bone_global_pose(bone_index).origin
		)
		var history: Array = joint_trails.get(bone_name, [])
		if not history.is_empty() and point.distance_to(history[-1]) > 0.8:
			history.clear()
		history.append(point)
		while history.size() > TRAIL_FRAMES:
			history.pop_front()
		joint_trails[bone_name] = history


func _draw_joint_chains(
	skeleton: Skeleton3D,
	chains: Array[Array],
	color: Color
) -> void:
	for chain in chains:
		var screen_points := PackedVector2Array()
		for raw_bone_name in chain:
			var bone_name := StringName(raw_bone_name)
			var bone_index := skeleton.find_bone(bone_name)
			if bone_index < 0:
				screen_points.clear()
				break
			var point: Vector3 = (
				skeleton.global_transform * skeleton.get_bone_global_pose(bone_index).origin
			)
			if camera.is_position_behind(point):
				screen_points.clear()
				break
			screen_points.append(camera.unproject_position(point))
		if screen_points.size() < 2:
			continue
		draw_polyline(screen_points, color, 3.0, true)
		for screen_point in screen_points:
			draw_circle(screen_point, 5.0, color)


func _draw_joint_trails() -> void:
	for raw_bone_name in joint_trails:
		var bone_name := StringName(raw_bone_name)
		var history: Array = joint_trails[bone_name]
		if history.size() < 2:
			continue
		var trail_color := (
			Color(0.14, 0.92, 1.0, 0.72)
			if "Hand" in String(bone_name)
			else Color(0.08, 0.76, 1.0, 0.72)
		)
		for index in range(1, history.size()):
			var previous: Vector3 = history[index - 1]
			var current: Vector3 = history[index]
			if camera.is_position_behind(previous) or camera.is_position_behind(current):
				continue
			var alpha := float(index) / float(history.size())
			var faded := trail_color
			faded.a *= alpha
			draw_line(
				camera.unproject_position(previous),
				camera.unproject_position(current),
				faded,
				2.0,
				true
			)


func _draw_weapon_pose(skeleton: Skeleton3D) -> void:
	var solver = driver.get("weapon_pose_solver")
	if solver == null or not bool(solver.get_debug_state().get("active", false)):
		return
	var target_specs: Array = [
		[&"mixamorig_RightHand", solver.trigger_hand_target, Color(1.0, 0.48, 0.12, 1.0)],
		[&"mixamorig_LeftHand", solver.support_hand_target, Color(1.0, 0.86, 0.18, 1.0)],
	]
	for spec in target_specs:
		var bone_index := skeleton.find_bone(StringName(spec[0]))
		var target: Node3D = spec[1]
		var color: Color = spec[2]
		if bone_index < 0 or target == null:
			continue
		var hand_world: Vector3 = (
			skeleton.global_transform * skeleton.get_bone_global_pose(bone_index).origin
		)
		var target_world := target.global_position
		if camera.is_position_behind(hand_world) or camera.is_position_behind(target_world):
			continue
		var hand_screen := camera.unproject_position(hand_world)
		var target_screen := camera.unproject_position(target_world)
		draw_line(hand_screen, target_screen, color, 2.0, true)
		draw_circle(target_screen, 7.0, color, false, 2.0, true)

	var weapon: Node3D = driver.get("weapon_node")
	if weapon == null:
		return
	var ray_start := weapon.global_position
	var ray_end: Vector3 = ray_start + solver.last_aim_direction * 1.25
	if camera.is_position_behind(ray_start) or camera.is_position_behind(ray_end):
		return
	draw_line(
		camera.unproject_position(ray_start),
		camera.unproject_position(ray_end),
		Color(1.0, 0.28, 0.18, 0.96),
		3.0,
		true
	)
