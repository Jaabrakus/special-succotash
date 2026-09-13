extends SceneTree

const Graph := preload("res://scripts/player/operator_locomotion_blend_tree.gd")

var scene: Node3D
var player: CharacterBody3D
var camera_rig: Node3D
var driver: Node
var solver: Node
var skeleton: Skeleton3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var packed: PackedScene = load("res://main.tscn")
	scene = packed.instantiate()
	root.add_child(scene)
	
	for f in 65:
		await physics_frame
		
	player = scene.get_node("Player") as CharacterBody3D
	camera_rig = scene.get_node("IndependentCameraRig") as Node3D
	driver = player.get_node("Mannequin/ProductionAnimation")
	solver = driver.get("weapon_pose_solver")
	skeleton = driver.get("skeleton")
	
	# Add a wide flat testing floor far away from walls/obstacles
	var test_floor := StaticBody3D.new()
	test_floor.position = Vector3(300.0, 0.0, 300.0)
	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(200.0, 1.0, 200.0)
	col.shape = box_shape
	col.position = Vector3(0.0, -0.5, 0.0)
	test_floor.add_child(col)
	scene.add_child(test_floor)
	
	camera_rig.profile.pitch_min_deg = -85.0
	camera_rig.profile.pitch_max_deg = 85.0
	
	print("--- BEGIN DEEP JUMP AIM PROBE ---")
	
	# Test with firing readiness active (notify_fired on jump or continuous ready)
	var pitches := [-85.0, -45.0, 0.0, 45.0, 85.0]
	var yaws := [0.0, 90.0, 180.0, 270.0]
	
	for pitch in pitches:
		for yaw in yaws:
			await _test_jump(pitch, yaw, [&"move_forward"], true)
			
	# Test stationary jump at extreme pitches
	await _test_jump(-85.0, 0.0, [], true)
	await _test_jump(0.0, 0.0, [], true)
	await _test_jump(85.0, 0.0, [], true)
	
	# Test all directions at pitch 0
	var dirs := [
		{"name": "Stationary", "acts": []},
		{"name": "Forward", "acts": [&"move_forward"]},
		{"name": "Back", "acts": [&"move_back"]},
		{"name": "Left", "acts": [&"move_left"]},
		{"name": "Right", "acts": [&"move_right"]},
		{"name": "Diag FL", "acts": [&"move_forward", &"move_left"]},
		{"name": "Diag FR", "acts": [&"move_forward", &"move_right"]},
		{"name": "Diag BL", "acts": [&"move_back", &"move_left"]},
		{"name": "Diag BR", "acts": [&"move_back", &"move_right"]},
	]
	for d in dirs:
		await _test_jump(0.0, 0.0, d.acts, true, d.name)
		
	print("--- END DEEP JUMP AIM PROBE ---")
	quit(0)

func _test_jump(pitch_deg: float, yaw_deg: float, actions: Array, with_fire: bool, label_override: String = "") -> void:
	for act in [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump"]:
		Input.action_release(act)
		
	# Place player on open test floor
	player.global_position = Vector3(300.0, 0.05, 300.0)
	player.velocity = Vector3.ZERO
	player.motion_state = player.MotionState.STANDING
	player.posture = player.MotionState.STANDING
	
	var yaw_rad := deg_to_rad(yaw_deg)
	var pitch_rad := deg_to_rad(pitch_deg)
	camera_rig.set_aim_angles(yaw_rad, pitch_rad, true)
	
	for f in 15:
		await physics_frame
		
	for act in actions:
		Input.action_press(act)
		
	if not actions.is_empty():
		for f in 25:
			await physics_frame
			
	var pre_rotations: Dictionary = {}
	for bone: StringName in Graph.JUMP_ARM_BONES:
		var b_idx := skeleton.find_bone(bone)
		if b_idx >= 0:
			pre_rotations[bone] = skeleton.get_bone_pose(b_idx).basis.get_rotation_quaternion()
			
	player.request_jump()
	await physics_frame
	
	var max_arm_delta := 0.0
	var max_trig := 0.0
	var max_supp := 0.0
	var max_bore := 0.0
	var air_frames := 0
	
	for frame in 80:
		await physics_frame
		var movement := StringName(player.call("get_motion_state_name"))
		if movement == &"AIRBORNE":
			air_frames += 1
			if with_fire and (air_frames == 1 or air_frames == 15):
				driver.notify_fired()
				
			for bone: StringName in Graph.JUMP_ARM_BONES:
				var b_idx := skeleton.find_bone(bone)
				if b_idx >= 0 and pre_rotations.has(bone):
					var cur_rot := skeleton.get_bone_pose(b_idx).basis.get_rotation_quaternion()
					max_arm_delta = maxf(max_arm_delta, cur_rot.angle_to(pre_rotations[bone]))
					
			var trig_err: float = float(solver.get("action_trigger_contact_error_m"))
			var supp_err: float = float(solver.get("support_hand_error_m"))
			var bore_err: float = float(solver.get("weapon_aim_error_deg"))
			
			max_trig = maxf(max_trig, trig_err)
			max_supp = maxf(max_supp, supp_err)
			# Sample bore error when weapon aim authority is active (after notify_fired has settled)
			if with_fire and air_frames >= 5:
				max_bore = maxf(max_bore, bore_err)
				
		if air_frames > 5 and movement != &"AIRBORNE" and player.is_on_floor():
			break
			
	for act in actions:
		Input.action_release(act)
		
	var name_str := label_override if label_override != "" else ("P%3.0f_Y%3.0f" % [pitch_deg, yaw_deg])
	print("RESULT: %-15s | air=%2d | arm_delta=%.4f | trig=%.4fm | supp=%.4fm | bore=%.2f deg" % [
		name_str, air_frames, max_arm_delta, max_trig, max_supp, max_bore
	])
