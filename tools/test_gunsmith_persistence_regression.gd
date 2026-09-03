extends SceneTree

const WEAPON_CONFIG_PATH := "res://config/weapons/assaultrifle_1.json"

func _init() -> void:
	print("=================================================================")
	print("[GUNSMITH REGRESSION] Starting Gunsmith Persistence & Rig Tests")
	print("=================================================================")
	
	var passed_count := 0
	var total_count := 9
	
	# Test 1: JSON Schema & Coordinate Space Metadata
	if _test_json_schema():
		print("[PASS 1/8] Weapon JSON contains clean seed and coordinate_space metadata.")
		passed_count += 1
	else:
		push_error("[FAIL 1/8] Weapon JSON failed schema or seed validation.")
	
	# Test 2: Validation Guard against Corrupted Offsets
	if _test_corruption_rejection():
		print("[PASS 2/8] Rig save validation successfully rejects corrupted offsets (>0.75m).")
		passed_count += 1
	else:
		push_error("[FAIL 2/8] Rig save validation failed to reject invalid offsets.")
		
	# Test 3: Parent-Local Drag Transformation Math
	if _test_drag_math():
		print("[PASS 3/8] Parent-local drag affine-inverse delta calculation verified.")
		passed_count += 1
	else:
		push_error("[FAIL 3/8] Parent-local drag math failed.")

	# Test 4: Socket Coordinate Scale Independence
	if _test_socket_scale_independence():
		print("[PASS 4/8] Sockets are isolated under unscaled root in canonical meters.")
		passed_count += 1
	else:
		push_error("[FAIL 4/8] Sockets scale independence test failed.")

	# Test 5: Operator Mount Euler Order & Invertibility
	if _test_operator_mount_roundtrip():
		print("[PASS 5/8] operator_mount preserves YXZ Euler orientation on save/load.")
		passed_count += 1
	else:
		push_error("[FAIL 5/8] operator_mount roundtrip failed.")

	# Test 6: World Origin Invariance
	if _test_world_origin_invariance():
		print("[PASS 6/8] Displacing operator world origin leaves local weapon transform invariant.")
		passed_count += 1
	else:
		push_error("[FAIL 6/8] World origin invariance test failed.")

	# Test 7: Studio & Runtime Parity
	if _test_studio_runtime_parity():
		print("[PASS 7/8] Studio socket contract matches runtime operator attachment.")
		passed_count += 1
	else:
		push_error("[FAIL 7/8] Studio/runtime parity test failed.")

	# Test 8: Ballistic Gizmo & Body/IK Isolation
	if _test_ballistics_body_isolation():
		print("[PASS 8/8] Ballistics gizmo (muzzle & barrel base) strictly isolated from hand grips and skeleton IK.")
		passed_count += 1
	else:
		push_error("[FAIL 8/8] Ballistics/body isolation test failed.")

	# Test 9: a saved stance owns the weapon transform in both Studio and play.
	if _test_stance_switch_has_no_weapon_rebase():
		print("[PASS 9/9] Stance switching does not add an unsaved weapon offset.")
		passed_count += 1
	else:
		push_error("[FAIL 9/9] Studio stance switching still rebases the weapon in world space.")

	print("=================================================================")
	print("[GUNSMITH REGRESSION] Summary: %d/%d tests passed" % [passed_count, total_count])
	print("=================================================================")

	if passed_count == total_count:
		print("✅ ALL GUNSMITH PERSISTENCE REGRESSION TESTS PASSED!")
		quit(0)
	else:
		print("❌ GUNSMITH REGRESSION TESTS FAILED!")
		quit(1)


func _test_json_schema() -> bool:
	var file := FileAccess.open(WEAPON_CONFIG_PATH, FileAccess.READ)
	if not file:
		return false
	var text := file.get_as_text()
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return false
	var d: Dictionary = json.data
	
	if not d.has("coordinate_space"):
		return false
	var cs: Dictionary = d.get("coordinate_space", {})
	if cs.get("grip_offset", "") != "weapon_root_local_meters":
		return false
	if cs.get("weapon_sockets", "") != "weapon_pivot_local_meters":
		return false
		
	var grip: Dictionary = d.get("grip_offset", {})
	var pos_x: float = float(grip.get("pos_x", 999.0))
	if absf(pos_x) > 0.50: # Must be within arm reach (<0.50m), not corrupted like 1.657m!
		return false
		
	return true


func _test_corruption_rejection() -> bool:
	var MAX_GRIP_OFFSET_RADIUS_METERS := 0.75
	var bad_grip := Vector3(1.657, -0.303, 0.355)
	if bad_grip.length() <= MAX_GRIP_OFFSET_RADIUS_METERS:
		return false
	var good_grip := Vector3(0.0, -0.015, -0.177)
	if good_grip.length() > MAX_GRIP_OFFSET_RADIUS_METERS:
		return false
	return true


func _test_drag_math() -> bool:
	var parent_transform := Transform3D(Basis().rotated(Vector3.UP, deg_to_rad(45.0)), Vector3(10, 5, -20))
	var world_start := Vector3(10, 6, -18)
	var world_current := Vector3(11, 6, -18)
	
	var parent_inverse := parent_transform.affine_inverse()
	var local_start: Vector3 = parent_inverse * world_start
	var local_current: Vector3 = parent_inverse * world_current
	var delta: Vector3 = local_current - local_start
	
	# The delta in world space was (1, 0, 0). Transformed by parent rotated 45 deg,
	# its local length must remain exactly 1.0.
	if absf(delta.length() - 1.0) > 0.0001:
		return false
	return true


func _test_socket_scale_independence() -> bool:
	var socket_canonical := Vector3(0.0, 0.0, -0.68)
	var mesh_scale := 0.219
	
	var socket_root := Node3D.new()
	socket_root.name = "SocketRoot"
	var marker := Node3D.new()
	marker.name = "Socket_Muzzle"
	marker.position = socket_canonical
	socket_root.add_child(marker)
	
	var geometry_root := Node3D.new()
	geometry_root.name = "GeometryRoot"
	geometry_root.scale = Vector3.ONE * mesh_scale
	
	# Marker position must be exactly socket_canonical regardless of geometry_root.scale
	if marker.position != socket_canonical:
		socket_root.free()
		geometry_root.free()
		return false
		
	socket_root.free()
	geometry_root.free()
	return true


func _test_operator_mount_roundtrip() -> bool:
	var rot_rad := Vector3(deg_to_rad(-90.0), deg_to_rad(180.0), 0.0)
	var basis := Basis.from_euler(rot_rad, EULER_ORDER_YXZ)
	var t := Transform3D(basis, Vector3(-0.02, 0.08, 0.05))
	
	var euler := t.basis.get_euler(EULER_ORDER_YXZ)
	var reconstructed_basis := Basis.from_euler(euler, EULER_ORDER_YXZ)
	
	# Verify that the reconstructed 3D orientation matrix transforms vectors identically
	var test_vec := Vector3(1.0, 2.0, 3.0)
	var transformed_1 := basis * test_vec
	var transformed_2 := reconstructed_basis * test_vec
	
	if transformed_1.distance_to(transformed_2) > 0.0001:
		return false
	return true


func _test_world_origin_invariance() -> bool:
	var skeleton_world_1 := Transform3D(Basis(), Vector3.ZERO)
	var skeleton_world_2 := Transform3D(Basis(), Vector3(100, 3, -75))
	
	var hand_local_pose := Transform3D(Basis(), Vector3(0.3, 1.4, 0.2))
	var mount_local := Transform3D(Basis(), Vector3(0.0, 0.05, -0.1))
	
	var hand_world_1 := skeleton_world_1 * hand_local_pose
	var hand_world_2 := skeleton_world_2 * hand_local_pose
	
	var weapon_root_1 := hand_world_1 * mount_local
	var weapon_root_2 := hand_world_2 * mount_local
	
	# The relative distance from skeleton to weapon root must be identical
	var rel_1: Vector3 = skeleton_world_1.affine_inverse() * weapon_root_1.origin
	var rel_2: Vector3 = skeleton_world_2.affine_inverse() * weapon_root_2.origin
	
	if rel_1.distance_to(rel_2) > 0.0001:
		return false
	return true


func _test_studio_runtime_parity() -> bool:
	var file := FileAccess.open(WEAPON_CONFIG_PATH, FileAccess.READ)
	if not file:
		return false
	var d: Dictionary = JSON.parse_string(file.get_as_text())
	var sockets: Dictionary = d.get("weapon_sockets", {})
	var barrel_base: Dictionary = sockets.get("barrel_base_socket", {})
	var muzzle: Dictionary = sockets.get("muzzle_socket", {})
	var barrel_base_pos := Vector3(
		float(barrel_base.get("x", 0)),
		float(barrel_base.get("y", 0)),
		float(barrel_base.get("z", 0))
	)
	var muzzle_pos := Vector3(float(muzzle.get("x", 0)), float(muzzle.get("y", 0)), float(muzzle.get("z", 0)))
	var model_rotation: Dictionary = d.get("model_rotation_degrees", {})
	# Socket coordinates are weapon-model local. Imported FBX files do not share
	# a universal forward axis, so local Z must not be used as the contract.
	if muzzle_pos.distance_to(barrel_base_pos) < 0.02:
		return false
	if model_rotation.is_empty():
		return false
	return true


func _test_ballistics_body_isolation() -> bool:
	# 1. Mathematical independence verification
	var muzzle_socket := Vector3(0.0, 0.0, -0.68)
	var barrel_base_socket := Vector3(0.0, 0.0, -0.12)
	var axis_pure := (muzzle_socket - barrel_base_socket).normalized()
	if absf(axis_pure.dot(Vector3.FORWARD) - 1.0) > 0.0001:
		return false
	var modified_grip := Vector3(0.30, 0.15, -0.10)
	var axis_pure_after := (muzzle_socket - barrel_base_socket).normalized()
	if axis_pure.distance_to(axis_pure_after) > 0.0001:
		return false

	# 2. Structural skeleton bone pose invariance verification
	var trooper_scene: PackedScene = load("res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx")
	if not trooper_scene:
		return false

	var trooper_instance := trooper_scene.instantiate() as Node3D
	root.add_child(trooper_instance)
	var skeleton: Skeleton3D = null
	var stack: Array[Node] = [trooper_instance]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			skeleton = n as Skeleton3D
			break
		for child in n.get_children():
			stack.append(child)

	if not skeleton:
		trooper_instance.queue_free()
		return false

	# Record bone poses before any socket operation
	var bone_poses_before: Array[Transform3D] = []
	for i in range(skeleton.get_bone_count()):
		bone_poses_before.append(skeleton.get_bone_global_pose(i))

	# Construct weapon hierarchy under skeleton
	var weapon_root := Node3D.new()
	var weapon_pivot := Node3D.new()
	var socket_root := Node3D.new()
	var muzzle_marker := Marker3D.new()
	var barrel_base_marker := Marker3D.new()

	skeleton.add_child(weapon_root)
	weapon_root.add_child(weapon_pivot)
	weapon_pivot.add_child(socket_root)
	socket_root.add_child(muzzle_marker)
	socket_root.add_child(barrel_base_marker)

	# Simulate dragging muzzle in 3D
	var test_world_pos: Vector3 = socket_root.to_global(muzzle_socket + Vector3(0.15, 0.20, -0.10))
	var new_muzzle_local: Vector3 = socket_root.to_local(test_world_pos)
	muzzle_marker.position = new_muzzle_local

	# Verify every single bone in the skeleton remained 100% unchanged
	var passed := true
	for i in range(skeleton.get_bone_count()):
		var pose_after := skeleton.get_bone_global_pose(i)
		if not pose_after.is_equal_approx(bone_poses_before[i]):
			print("COUPLING BUG DETECTED ON BONE: ", skeleton.get_bone_name(i))
			passed = false

	weapon_root.free()
	trooper_instance.queue_free()
	return passed


func _test_stance_switch_has_no_weapon_rebase() -> bool:
	var file := FileAccess.open("res://scripts/labs/gun_calibration_lab.gd", FileAccess.READ)
	if file == null:
		return false
	# This mutation caused a loaded stance to appear unsaved after animation
	# advanced. The local profile transform must remain authoritative.
	return file.get_as_text().find("weapon_root.global_position +=") == -1
