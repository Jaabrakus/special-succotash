extends SceneTree

const Graph := preload("res://scripts/player/operator_locomotion_blend_tree.gd")

var failures: Array[String] = []
var scene: Node3D
var driver: Node
var player: CharacterBody3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	scene = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(65)
	player = scene.get_node("Player") as CharacterBody3D
	driver = player.get_node("Mannequin/ProductionAnimation")
	var graph = driver.get("locomotion_graph")
	var tree: AnimationTree = graph.animation_tree
	var skeleton: Skeleton3D = driver.get("skeleton")

	# 1. Structural checks on blend graph
	var blend: AnimationNodeBlend2 = tree.tree_root.get_node(&"jump_lower_body")
	for bone: StringName in Graph.JUMP_ARM_BONES:
		_check(blend.is_path_filtered(NodePath(".:%s" % bone)), "arm filter includes " + String(bone))
	for bone: StringName in Graph.JUMP_TORSO_BONES:
		_check(blend.is_path_filtered(NodePath(".:%s" % bone)), "torso filter includes " + String(bone))
	_check(not graph._uses_upper_body_ready_layer(graph.jump_lower_body_clip), "jump lower body clip excludes grounded ready layer")

	# 2. Record pre-jump resting arm rotations
	var pre_jump_arm_rotations: Dictionary = {}
	for bone: StringName in Graph.JUMP_ARM_BONES:
		var b_idx := skeleton.find_bone(bone)
		if b_idx >= 0:
			pre_jump_arm_rotations[bone] = skeleton.get_bone_pose(b_idx).basis.get_rotation_quaternion()

	# 3. Perform airborne jump with firing readiness
	var max_arm_delta := 0.0
	var max_trigger_contact := 0.0
	var max_support_contact := 0.0
	var min_bore_error_during_fire := 999.0
	var saw_air := false

	Input.action_press(&"jump")
	await physics_frame
	Input.action_release(&"jump")

	for frame in 160:
		await physics_frame
		var movement := StringName(player.call("get_motion_state_name"))
		if movement == &"AIRBORNE":
			saw_air = true
			# Sample arm animation delta
			for bone: StringName in Graph.JUMP_ARM_BONES:
				var b_idx := skeleton.find_bone(bone)
				if b_idx >= 0 and pre_jump_arm_rotations.has(bone):
					var cur_rot := skeleton.get_bone_pose(b_idx).basis.get_rotation_quaternion()
					max_arm_delta = maxf(max_arm_delta, cur_rot.angle_to(pre_jump_arm_rotations[bone]))
			var solver: Node = driver.get("weapon_pose_solver")
			if solver != null:
				max_trigger_contact = maxf(max_trigger_contact, float(solver.get("action_trigger_contact_error_m")))
				max_support_contact = maxf(max_support_contact, float(solver.get("support_hand_error_m")))
				# Trigger fire while airborne to test weapon aim authority mid-air
				if frame == 25:
					driver.notify_fired()
				if frame >= 25 and frame <= 35:
					min_bore_error_during_fire = minf(min_bore_error_during_fire, float(solver.get("weapon_aim_error_deg")))
		if saw_air and movement == &"LOCOMOTION" and player.is_on_floor():
			break

	await _frames(8)
	_check(saw_air, "jump reached airborne motion state")
	_check(max_arm_delta > 0.10, "upper-body arm tracks visibly animate during airborne flight (rotational delta > 0.10 rad, was %.4f)" % max_arm_delta)
	_check(max_trigger_contact <= 0.015, "trigger hand contact <= 0.015m (was %.4fm)" % max_trigger_contact)
	_check(max_support_contact <= 0.020, "support hand contact <= 0.020m (was %.4fm)" % max_support_contact)
	_check(min_bore_error_during_fire <= 6.0, "bore to reticle degrees <= 6.0° during mid-air fire (was %.2f°)" % min_bore_error_during_fire)

	print("JUMP_ACTION_ARM_REGRESSION %s max_arm_delta=%.4f trigger_contact=%.4f support_contact=%.4f fire_bore_deg=%.2f" % [
		"PASS" if failures.is_empty() else "FAIL",
		max_arm_delta,
		max_trigger_contact,
		max_support_contact,
		min_bore_error_during_fire
	])
	if not failures.is_empty():
		for f in failures:
			push_error("JUMP_ACTION_ARM: " + f)
	quit(0 if failures.is_empty() else 1)


func _frames(count: int) -> void:
	for frame in count:
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)
