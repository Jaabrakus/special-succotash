extends "res://tools/firearm_family_transition_regression.gd"

## Read-only generic model surface evidence; never edits contacts or profiles.
## --weapons=m14,m16a2-m203,m4a1_sd,m4a1-m203 [--capture] --output-prefix=...
var inspected_ids: Dictionary = {}
var inspection_weapon_id := ""
var surface_output_prefix := ""


func _initialize() -> void:
	super._initialize()
	if selected_ids.is_empty():
		selected_ids.assign(["m14", "m16a2-m203", "m4a1_sd", "m4a1-m203"])
	for id in selected_ids:
		if id not in ["m14", "m16a2-m203", "m4a1_sd", "m4a1-m203"]:
			_fail_once("Requested surface model is outside the declared long-fore-end scope")

func _check_stance(_stance: int) -> void:
	if inspected_ids.has(weapon_id):
		return
	inspected_ids[weapon_id] = true
	inspection_weapon_id = weapon_id
	surface_output_prefix = output_prefix + "-" + weapon_id
	var pose: Node3D = driver.get("weapon_pose_solver")
	var weapon: Node3D = pose.get("weapon_node")
	var config: Dictionary = Contract.load_config("res://config/weapons/%s.json" % inspection_weapon_id)
	var batch: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapon_directional_batch_candidates.json"))
	var registry_entry: Dictionary = batch.weapons[inspection_weapon_id]
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapon_visual_rigs/%s.json" % registry_entry.base_rig))
	var base: Dictionary = original.visual.weapon_sockets.left_hand_ik_target
	var candidate: Dictionary = config.weapon_sockets.left_hand_ik_target
	var points: Dictionary = {
		"base_fore_end": Vector3(float(base.x), float(base.y), float(base.z)),
		"candidate_current": Vector3(float(candidate.x), float(candidate.y), float(candidate.z)),
	}
	for backward: float in [0.04, 0.08, 0.12, 0.16, 0.20]:
		points["rearward_%.2f" % backward] = Vector3(float(base.x), float(base.y), float(base.z) - backward)
	var socket_parent := pose.support_socket.get_parent() as Node3D
	var socket_to_weapon := weapon.global_transform.affine_inverse() * socket_parent.global_transform
	var source_points := points.duplicate()
	for label: String in points:
		points[label] = socket_to_weapon * (points[label] as Vector3)
	var meshes: Array[Dictionary] = []
	var faces := PackedVector3Array()
	var bounds := AABB()
	var has_bounds := false
	var stage := Node3D.new()
	stage.name = "ReadOnlyGenericSurfaceReview"
	root.add_child(stage)
	for node: Node in weapon.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null or not mesh_node.is_visible_in_tree():
			continue
		var to_weapon := weapon.global_transform.affine_inverse() * mesh_node.global_transform
		var local_faces := mesh_node.mesh.get_faces()
		if local_faces.is_empty():
			continue
		var first := faces.size()
		for point: Vector3 in local_faces:
			var transformed: Vector3 = to_weapon * point
			faces.append(transformed)
			if not has_bounds:
				bounds = AABB(transformed, Vector3.ZERO)
				has_bounds = true
			else:
				bounds = bounds.expand(transformed)
		meshes.append({"path":str(weapon.get_path_to(mesh_node)), "start":first, "count":local_faces.size()})
		var display := MeshInstance3D.new()
		display.mesh = mesh_node.mesh
		stage.add_child(display)
		display.transform = to_weapon
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.58, 0.64, 0.70)
		material.roughness = 0.9
		display.material_override = material
	if faces.is_empty():
		_fail_once("Canonical generic weapon has no inspectable visible mesh faces")
		stage.queue_free()
		return
	var report := {"canonical_scene":"res://main.tscn", "weapon":inspection_weapon_id, "mesh":config.model_fbx,
		"weapon_world_scale":str(weapon.global_basis.get_scale()), "meshes":meshes,
		"bounds":str(bounds), "points":{}, "profile_changed":false,
		"socket_parent":str(weapon.get_path_to(socket_parent)), "socket_to_weapon":str(socket_to_weapon)}
	for label: String in points:
		var target: Vector3 = points[label]
		var best_distance := INF
		var best_point := Vector3.INF
		var best_face := -1
		for index in range(0, faces.size(), 3):
			var closest := _closest_triangle(target, faces[index], faces[index + 1], faces[index + 2])
			var distance := target.distance_to(closest)
			if distance < best_distance:
				best_distance = distance
				best_point = closest
				best_face = index
		var mesh_path := ""
		for entry: Dictionary in meshes:
			if best_face >= int(entry.start) and best_face < int(entry.start) + int(entry.count):
				mesh_path = String(entry.path)
		var source_surface := socket_to_weapon.affine_inverse() * best_point
		report.points[label] = {"position":str(target), "source_socket_position":str(source_points[label]), "nearest_surface_m":best_distance,
			"nearest_surface_socket_position":{"x":source_surface.x, "y":source_surface.y, "z":source_surface.z},
			"nearest_surface_point":str(best_point), "nearest_mesh":mesh_path}
		var marker := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.012
		sphere.height = 0.024
		marker.mesh = sphere
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color.LIME_GREEN if label == "base_fore_end" else Color.ORANGE_RED
		if label == "candidate_current":
			material.albedo_color = Color.CYAN
		material.no_depth_test = true
		marker.material_override = material
		stage.add_child(marker)
		marker.position = target
	if capture:
		var previous_camera := root.get_camera_3d()
		var review_camera := Camera3D.new()
		stage.add_child(review_camera)
		review_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		review_camera.size = bounds.size.length() * 1.15
		var light := DirectionalLight3D.new()
		stage.add_child(light)
		light.rotation_degrees = Vector3(-35, -25, 0)
		light.light_energy = 2.0
		var second := DirectionalLight3D.new()
		stage.add_child(second)
		second.rotation_degrees = Vector3(40, 150, 0)
		second.light_energy = 0.65
		var environment := WorldEnvironment.new()
		stage.add_child(environment)
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(0.08, 0.10, 0.12)
		review_camera.environment = environment.environment
		scene.visible = false
		paused = true
		var center := bounds.get_center()
		for view: String in ["side", "oblique", "underside"]:
			var view_direction := Vector3(1, 0.08, 0)
			if view == "oblique":
				view_direction = Vector3(1, 0.45, 0.75)
			elif view == "underside":
				view_direction = Vector3(1, -0.8, 0.2)
			review_camera.position = center + socket_to_weapon.basis * view_direction.normalized() * 3
			review_camera.look_at(center, socket_to_weapon.basis * Vector3.UP)
			review_camera.make_current()
			await process_frame
			await RenderingServer.frame_post_draw
			var path := surface_output_prefix + "-" + view + ".png"
			if root.get_texture().get_image().save_png(path) != OK:
				_fail_once("Failed to save surface review image: " + path)
			report[view + "_image"] = path
		if previous_camera != null:
			previous_camera.make_current()
		paused = false
		scene.visible = true
	var file := FileAccess.open(surface_output_prefix + "-surface.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("GENERIC_SURFACE ", JSON.stringify(report))
	stage.queue_free()


func _finish() -> void:
	_release_inputs()
	paused = false
	print("GENERIC_CONTACT_SURFACE_INSPECTION ", "COMPLETE" if failures.is_empty() else "FAIL", " (not a physical pose gate) ", failures)
	quit(0 if failures.is_empty() else 1)


func _closest_triangle(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() > 0.000000000001:
		var projected := point - normal * normal.dot(point - a) / normal.length_squared()
		if (b-a).cross(projected-a).dot(normal) >= 0.0 and (c-b).cross(projected-b).dot(normal) >= 0.0 and (a-c).cross(projected-c).dot(normal) >= 0.0:
			return projected
	var closest := _closest_segment(point, a, b)
	for candidate: Vector3 in [_closest_segment(point, b, c), _closest_segment(point, c, a)]:
		if point.distance_squared_to(candidate) < point.distance_squared_to(closest):
			closest = candidate
	return closest


func _closest_segment(point: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var edge := b - a
	if edge.length_squared() <= 0.000000000001:
		return a
	return a + edge * clampf((point-a).dot(edge) / edge.length_squared(), 0.0, 1.0)
