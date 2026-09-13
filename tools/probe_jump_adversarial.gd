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
	
	# Enable full pitch range on camera profile for testing
	camera_rig.profile.pitch_min_deg = -85.0
	camera_rig.profile.pitch_max_deg = 85.0
	
	print("--- BEGIN ADVERSARIAL JUMP PROBE ---")
	
	var test_cases: Array[Dictionary] = [
		{"name": "Stationary Pitch 0 Yaw 0", "dir": [], "pitch": 0.0, "yaw": 0.0, "fire": false},
		{"name": "Forward Pitch 0 Yaw 0", "dir": [&"move_forward"], "pitch": 0.0, "yaw": 0.0, "fire": false},
		{"name": "Forward Pitch -85 Yaw 0", "dir": [&"move_forward"], "pitch": -85.0, "yaw": 0.0, "fire": false},
		{"name": "Forward Pitch +85 Yaw 0", "dir": [&"move_forward"], "pitch": 85.0, "yaw": 0.0, "fire": false},
		{"name": "Left Pitch 0 Yaw 90", "dir": [&"move_left"], "pitch": 0.0, "yaw": 90.0, "fire": false},
		{"name": "Right Pitch -85 Yaw 180", "dir": [&"move_right"], "pitch": -85.0, "yaw": 180.0, "fire": false},
		{"name": "Back Pitch +85 Yaw 270", "dir": [&"move_back"], "pitch": 85.0, "yaw": 270.0, "fire": false},
		{"name": "Diag FL Pitch 0 Yaw 0 + Fire", "dir": [&"move_forward", &"move_left"], "pitch": 0.0, "yaw": 0.0, "fire": true},
	]
	
	for tc in test_cases:
		await _run_test_case(tc)
		
	print("--- END ADVERSARIAL JUMP PROBE ---")
	quit(0)

func _run_test_case(tc: Dictionary) -> void:
	# Reset player
	player.global_position = Vector3(0.0, 0.05, 0.0)
	player.velocity = Vector3.ZERO
	for act in [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump"]:
		Input.action_release(act)
		
	# Apply camera aim
	var yaw_rad := deg_to_rad(float(tc.yaw))
	var pitch_rad := deg_to_rad(float(tc.pitch))
	camera_rig.set_aim_angles(yaw_rad, pitch_rad, true)
	
	for f in 15:
		await physics_frame
		
	# Apply movement actions
	var actions: Array = tc.dir
	for act in actions:
		Input.action_press(act)
		
	if not actions.is_empty():
		for f in 25:
			await physics_frame
			
	# Record pre-jump arm rotations
	var pre_rotations: Dictionary = {}
	for bone: StringName in Graph.JUMP_ARM_BONES:
		var b_idx := skeleton.find_bone(bone)
		if b_idx >= 0:
			pre_rotations[bone] = skeleton.get_bone_pose(b_idx).basis.get_rotation_quaternion()
			
	# Request jump
	player.request_jump()
	await physics_frame
	
	var max_arm_delta := 0.0
	var max_trigger_contact := 0.0
	var max_support_contact := 0.0
	var max_bore_error := 0.0
	var airborne_frames := 0
	
	for frame in 80:
		await physics_frame
		var movement := StringName(player.call("get_motion_state_name"))
		if movement == &"AIRBORNE":
			airborne_frames += 1
			# Measure arm delta
			for bone: StringName in Graph.JUMP_ARM_BONES:
				var b_idx := skeleton.find_bone(bone)
				if b_idx >= 0 and pre_rotations.has(bone):
					var cur_rot := skeleton.get_bone_pose(b_idx).basis.get_rotation_quaternion()
					max_arm_delta = maxf(max_arm_delta, cur_rot.angle_to(pre_rotations[bone]))
			# Measure contacts
			var trig_err: float = float(solver.get("action_trigger_contact_error_m"))
			var supp_err: float = float(solver.get("support_hand_error_m"))
			var bore_err: float = float(solver.get("weapon_aim_error_deg"))
			max_trigger_contact = maxf(max_trigger_contact, trig_err)
			max_support_contact = maxf(max_support_contact, supp_err)
			max_bore_error = maxf(max_bore_error, bore_err)
			
			if tc.fire and frame == 25:
				driver.notify_fired()
				
		if airborne_frames > 5 and movement != &"AIRBORNE" and player.is_on_floor():
			break
			
	for act in actions:
		Input.action_release(act)
		
	print("PROBE_CASE: %-30s | air_frames=%2d | arm_delta=%.4f (req>0.10) | trig=%.4fm (req<=0.015) | supp=%.4fm (req<=0.020) | bore=%.2f deg (req<=6.0)" % [
		tc.name, airborne_frames, max_arm_delta, max_trigger_contact, max_support_contact, max_bore_error
	])
