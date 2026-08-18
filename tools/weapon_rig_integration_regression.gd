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

	var shot: Dictionary = controller.call("request_fire")
	_expect(bool(shot.get("fired", false)), "authoritative weapon fires from equipped contract")
	if bool(shot.get("fired", false)):
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
			and pivot.position.is_equal_approx(Vector3(0.01, 0.02, 0.03)),
		"Gunsmith per-animation hand map reaches gameplay by clip basename"
	)
	_expect(
		not runtime.apply_animation_hand_map("res://clips/idle.fbx")
			and left.position.is_equal_approx(Vector3.ZERO)
			and right.position.is_equal_approx(Vector3.ZERO)
			and pivot.position.is_equal_approx(Vector3.ZERO),
		"leaving a mapped action restores stable weapon and hand sockets"
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
