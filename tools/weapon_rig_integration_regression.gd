extends SceneTree

const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const AssetRuntime := preload("res://scripts/player/operator_asset_runtime.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config_path := WeaponContract.resolve_config_path()
	_expect(not config_path.is_empty(), "canonical operator loadout selects a weapon profile")
	var config := WeaponContract.load_equipped_config()
	_expect(int(config.get("schema_version", 0)) == 3, "equipped weapon uses current contract schema")
	_expect(String(config.get("_rig_config_path", "")) == config_path, "all consumers retain one source profile path")
	_expect(
		config.has("socket_contract_authored"),
		"format version and human-authored socket status are separate"
	)
	var sockets: Dictionary = config.get("weapon_sockets", {})
	for socket_name in [
		"right_hand_grip_target",
		"left_hand_ik_target",
		"barrel_base_socket",
		"muzzle_socket",
		"ejection_port",
		"optic_rail",
	]:
		_expect(sockets.has(socket_name), "contract exposes %s" % socket_name)
	var configured_velocity := float((config.get("ballistics", {}) as Dictionary).get("muzzle_velocity_mps", 0.0))
	_expect(configured_velocity > 100.0, "equipped profile carries physical muzzle velocity")
	_test_animation_hand_map_contract()

	# Every older profile must normalize to the same complete in-memory shape;
	# this is the compatibility promise that keeps existing Gunsmith work usable.
	var weapon_dir := DirAccess.open("res://config/weapons")
	if weapon_dir != null:
		for file_name in weapon_dir.get_files():
			if not file_name.ends_with(".json") or file_name == "operator_loadout.json":
				continue
			var candidate := WeaponContract.load_config("res://config/weapons/%s" % file_name)
			var candidate_sockets: Dictionary = candidate.get("weapon_sockets", {})
			_expect(
				int(candidate.get("schema_version", 0)) == 3
				and candidate_sockets.has("right_hand_grip_target")
				and candidate_sockets.has("barrel_base_socket")
				and float((candidate.get("ballistics", {}) as Dictionary).get("muzzle_velocity_mps", 0.0)) > 100.0,
				"legacy profile %s upgrades without losing authored fields" % file_name
			)

	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "canonical gameplay scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _steps(50)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var rig := scene.get_node_or_null("IndependentCameraRig")
	var controller := scene.get_node_or_null("WeaponController")
	_expect(player != null and rig != null and controller != null, "gameplay weapon path is live")
	if player == null or rig == null or controller == null:
		scene.queue_free()
		_finish()
		return

	var mannequin := player.get_node_or_null("Mannequin")
	var active_muzzle: Marker3D = mannequin.call("get_active_muzzle_marker")
	var active_barrel_base: Marker3D = mannequin.call("get_active_barrel_base_marker")
	var active_right: Marker3D = mannequin.call("get_active_weapon_socket", &"Socket_RightHand")
	var active_left: Marker3D = mannequin.call("get_active_weapon_socket", &"Socket_LeftHand")
	var active_ejection: Marker3D = mannequin.call("get_active_ejection_marker")
	var active_optic: Marker3D = mannequin.call("get_active_optic_marker")
	_expect(
		active_muzzle != null and active_barrel_base != null
			and active_right != null and active_left != null
			and active_ejection != null and active_optic != null,
		"rendered operator receives grip, barrel, muzzle, ejection, and optic sockets"
	)
	var weapon_mesh := mannequin.find_child("WeaponMesh", true, false) as Node3D
	var rendered_weapon_span := _rendered_mesh_span(weapon_mesh)
	print("WEAPON_RIG_INTEGRATION_METRIC rendered_weapon_span_m=%.4f" % rendered_weapon_span)
	_expect(
		rendered_weapon_span >= 0.45 and rendered_weapon_span <= 1.0,
		"equipped rifle is human-scale instead of using raw FBX dimensions"
	)
	_expect(
		is_equal_approx(float(controller.ballistics.muzzle_velocity_mps), configured_velocity),
		"live ballistics imports Gunsmith muzzle velocity"
	)
	await _test_live_stance_rig(player, mannequin, config)

	var shot: Dictionary = controller.call("request_fire")
	_expect(bool(shot.get("fired", false)), "authoritative weapon fires from equipped contract")
	if bool(shot.get("fired", false)):
		var production = mannequin.get("production_animation")
		var animation_debug: Dictionary = (
			production.call("get_animation_debug_state")
			if production != null
			else {}
		)
		var animation_slots: Dictionary = config.get("handling_profile", {}).get("animation_slots", {})
		_expect(
			int(animation_debug.get("fire_trigger_count", 0)) > 0
			and StringName(animation_debug.get("active_fire_clip", &""))
				== StringName(animation_slots.get("fire_prone", "prone_fire")),
			"real gameplay fire triggers the equipped posture-specific animation layer"
		)
		_expect(
			Vector3(shot.get("origin", Vector3.INF)).distance_to(active_muzzle.global_position) <= 0.002,
			"shot starts at rendered red muzzle socket"
		)
		_expect(
			is_equal_approx(float(shot.get("muzzle_velocity_mps", 0.0)), configured_velocity),
			"shot result carries velocity into presentation"
		)
		var expected_travel := Vector3(shot.hit_pos).distance_to(Vector3(shot.origin)) / configured_velocity
		_expect(
			absf(float(shot.get("tracer_travel_seconds", -1.0)) - expected_travel) <= 0.0001,
			"tracer timing derives from saved velocity while hit detection stays hitscan"
		)
		var alignment_error := float(shot.get("barrel_alignment_error_deg", NAN))
		_expect(
			not is_nan(alignment_error) and not is_inf(alignment_error),
			"shot reports rendered-barrel alignment for regression auditing"
		)
		var visible_shell := false
		for candidate in scene.find_children("PooledShell_*", "MeshInstance3D", true, false):
			if (candidate as MeshInstance3D).visible:
				visible_shell = true
				break
		_expect(visible_shell, "ejection socket drives pooled shell presentation")

	scene.queue_free()
	_finish()


func _test_live_stance_rig(player: CharacterBody3D, mannequin: Node, config: Dictionary) -> void:
	var production = mannequin.get("production_animation")
	_expect(production != null, "production animation driver is available for stance rig audit")
	if production == null:
		return
	var runtime = production.get("asset_runtime")
	var solver = production.get("weapon_pose_solver")
	_expect(runtime != null and solver != null, "runtime weapon and post-animation solver are available")
	if runtime == null or solver == null:
		return
	var grip: Dictionary = config.get("grip_offset", {})
	var expected_position := Vector3(
		float(grip.get("pos_x", 0.0)),
		float(grip.get("pos_y", 0.0)),
		float(grip.get("pos_z", 0.0))
	)
	for stance_case in [
		{"name": &"STANDING", "value": 0},
		{"name": &"CROUCHED", "value": 1},
		{"name": &"PRONE", "value": 2},
	]:
		player.set("posture", int(stance_case.value))
		player.set("motion_state", int(stance_case.value))
		player.call("_apply_posture_collider")
		await _steps(12)
		var stance_name := StringName(stance_case.name)
		var pivot: Node3D = runtime.get("calibrated_weapon_pivot") as Node3D
		_expect(
			pivot != null and pivot.position.distance_to(expected_position) <= 0.001,
			"%s keeps the one weapon-level mount after gameplay frames" % stance_name
		)
		var debug: Dictionary = solver.call("get_debug_state")
		print(
			"WEAPON_RIG_STANCE_METRIC %s weight=%.3f trigger=%.4f support=%.4f mount=%s" % [
				stance_name,
				float(debug.get("weight", 0.0)),
				float(debug.get("trigger_hand_error_m", 1.0)),
				float(debug.get("support_hand_error_m", 1.0)),
				str(expected_position),
			]
		)
		print("WEAPON_RIG_HAND_METRIC %s left=%s target=%s" % [
			String(stance_name),
			str(debug.get("support_hand_position", Vector3.ZERO)),
			str(debug.get("support_hand_target", Vector3.ZERO)),
		])
		var live_skeleton := solver.get("skeleton") as Skeleton3D
		var live_weapon := solver.get("weapon_node") as Node3D
		var left_shoulder := live_skeleton.global_transform * live_skeleton.get_bone_global_pose(
			live_skeleton.find_bone("mixamorig_LeftArm")
		).origin
		var left_elbow := live_skeleton.global_transform * live_skeleton.get_bone_global_pose(
			live_skeleton.find_bone("mixamorig_LeftForeArm")
		).origin
		var left_hand := live_skeleton.global_transform * live_skeleton.get_bone_global_pose(
			live_skeleton.find_bone("mixamorig_LeftHand")
		).origin
		var support_socket := live_weapon.find_child("Socket_LeftHand", true, false) as Marker3D
		print("WEAPON_RIG_REACH_METRIC %s target=%.4f reach=%.4f" % [
			String(stance_name),
			left_shoulder.distance_to(support_socket.global_position),
			left_shoulder.distance_to(left_elbow) + left_elbow.distance_to(left_hand),
		])
		_expect(
			float(debug.get("trigger_hand_error_m", 1.0)) <= 0.035,
			"%s trigger hand remains attached to the saved weapon rig" % stance_name
		)
		_expect(
			float(debug.get("support_hand_error_m", 1.0)) <= 0.055,
			"%s support hand remains attached to the saved weapon rig" % stance_name
		)


func _test_animation_hand_map_contract() -> void:
	var runtime = AssetRuntime.new()
	var weapon := Node3D.new()
	var pivot := Node3D.new()
	var left := Marker3D.new()
	var right := Marker3D.new()
	left.name = "Socket_LeftHand"
	right.name = "Socket_RightHand"
	pivot.add_child(left)
	pivot.add_child(right)
	weapon.add_child(pivot)
	runtime.weapon_node = weapon
	runtime.calibrated_weapon_pivot = pivot
	runtime.equipped_weapon_config = {
		"support_hand_pose": {"palm_roll_deg": 4.0},
		"animation_hand_maps": {
			"res://clips/reload.fbx": {
				"left_grip": {"x": 0.2, "y": 0.3, "z": 0.4},
				"right_grip": {"x": -0.1, "y": 0.05, "z": 0.02},
				"weapon_mount_position": {"x": 0.01, "y": 0.02, "z": 0.03},
				"weapon_mount_rotation_deg": {"x": 4.0, "y": 5.0, "z": 6.0},
				"palm_roll_deg": 18.0,
			}
		}
	}
	runtime.call("_cache_weapon_map_baseline")
	_expect(
		runtime.apply_animation_hand_map("res://other/reload.fbx")
			and left.position.is_equal_approx(Vector3(0.2, 0.3, 0.4))
			and right.position.is_equal_approx(Vector3(-0.1, 0.05, 0.02))
			and pivot.position.is_equal_approx(Vector3.ZERO),
		"per-animation hand sockets reach gameplay without moving the weapon anchor"
	)
	_expect(
		not runtime.apply_animation_hand_map("res://clips/idle.fbx")
			and left.position.is_equal_approx(Vector3.ZERO)
			and right.position.is_equal_approx(Vector3.ZERO)
			and pivot.position.is_equal_approx(Vector3.ZERO),
		"leaving a mapped action restores stable weapon and hand sockets"
	)
	runtime.equipped_weapon_config["stances"] = {
		"STANDING": {
			"left_grip": {"x": 0.4, "y": 0.1, "z": -0.2},
			"right_grip": {"x": 0.0, "y": 0.0, "z": 0.0},
			"weapon_mount_position": {"x": 0.08, "y": 0.04, "z": 0.12},
			"weapon_mount_rotation_deg": {"x": 1.0, "y": 2.0, "z": 3.0},
		}
	}
	_expect(
		runtime.apply_animation_hand_map("res://clips/run_forward.fbx", &"STANDING")
			and left.position.is_equal_approx(Vector3(0.4, 0.1, -0.2))
			and pivot.position.is_equal_approx(Vector3.ZERO),
		"explicit gameplay stance adjusts hands without moving the weapon anchor"
	)
	weapon.free()


func _steps(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _rendered_mesh_span(node: Node3D) -> float:
	if node == null:
		return 0.0
	var points: Array[Vector3] = []
	_collect_mesh_points(node, points)
	if points.is_empty():
		return 0.0
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))


func _collect_mesh_points(node: Node, points: Array[Vector3]) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var bounds := mesh_node.get_aabb()
		for x in [0.0, 1.0]:
			for y in [0.0, 1.0]:
				for z in [0.0, 1.0]:
					points.append(
						mesh_node.global_transform
						* (bounds.position + bounds.size * Vector3(x, y, z))
					)
	for child in node.get_children():
		_collect_mesh_points(child, points)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("WEAPON_RIG_INTEGRATION_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("WEAPON_RIG_INTEGRATION_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("WEAPON_RIG_INTEGRATION_REGRESSION PASS")
		quit(0)
	else:
		print("WEAPON_RIG_INTEGRATION_REGRESSION FAIL ", failures)
		quit(1)
