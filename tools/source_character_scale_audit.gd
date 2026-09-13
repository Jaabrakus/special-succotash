extends SceneTree
## Read-only fresh main observation. No saved assets/profiles/runtime are edited.

const SOURCE_METRES_PER_UNIT := 0.10000000149011612
var scene: Node3D
var player: CharacterBody3D
var driver: Node
var skeleton: Skeleton3D
var report: Dictionary = {"schema_version": 1, "stances": [], "errors": []}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	scene = load("res://main.tscn").instantiate()
	scene.get_node("IndependentCameraRig").capture_mouse_on_ready = false
	root.add_child(scene)
	player = scene.get_node("Player")
	player.set_local_input_enabled(false)
	scene.get_node("IndependentCameraRig").orbit_input_enabled = false
	await _frames(90)
	scene.get_node("WeaponController").set_input_enabled(false)
	driver = player.get_node("Mannequin/ProductionAnimation")
	skeleton = driver.skeleton
	var model: Node3D = driver.model_root
	report["selected_config"] = JSON.parse_string(FileAccess.get_file_as_string("res://config/operator_character.json"))
	report["actual_model"] = model.scene_file_path
	report["actual_model_sha256"] = FileAccess.get_sha256(model.scene_file_path)
	report["model_transform"] = _transform(model.transform)
	report["model_global_transform"] = _transform(model.global_transform)
	report["skeleton_transform"] = _transform(skeleton.transform)
	report["skeleton_global_transform"] = _transform(skeleton.global_transform)
	report["player_transform"] = _transform(player.transform)
	report["driver_transform"] = _transform(driver.transform)
	report["mannequin_transform"] = _transform(player.get_node("Mannequin").transform)
	report["rest_bounds"] = _skin_bounds(true)
	report["rest_landmarks"] = _landmarks(true)
	var iso: Dictionary = skeleton.get_meta("iso_proportions", {})
	report["iso_metadata"] = iso
	if not iso.is_empty():
		var ratio: float = SOURCE_METRES_PER_UNIT / float(iso.metres_per_source_unit)
		report["source_unit_scale"] = SOURCE_METRES_PER_UNIT
		report["verified_skeleton_uniform_scale_ratio"] = ratio
		report["candidate_model_scale_if_only_this_discrepancy_corrected"] = model.scale.x * ratio
	for stance in [0, 1, 2]:
		var accepted: bool = player.call("_try_set_posture", stance)
		if not accepted:
			report.errors.append("Posture refused " + str(stance))
			continue
		await _frames(60)
		var capsule: CapsuleShape3D = player.get_node("CollisionShape3D").shape
		var markers := {}
		for name in ["HeadMarker", "TorsoMarker", "PelvisMarker", "FeetMarker"]:
			var marker := player.get_node("Mannequin").get_node_or_null(name) as Node3D
			if marker != null:
				markers[name] = _vec(player.to_local(marker.global_position))
		var debug: Dictionary = driver.get_animation_debug_state()
		report.stances.append({"posture": stance, "logical_clip": debug.get("logical_clip", ""),
			"on_floor": player.is_on_floor(), "motion_state": player.get("motion_state"),
			"capsule_height_m": capsule.height, "capsule_radius_m": capsule.radius,
			"capsule_center": _vec(player.get_node("CollisionShape3D").position),
			"markers_player_local": markers, "landmarks_player_local": _landmarks(false),
			"skinned_bounds_player_local": _skin_bounds(false)})
	print("SOURCE_CHARACTER_SCALE_AUDIT ", JSON.stringify(report))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			var out := argument.trim_prefix("--out=")
			if not out.begins_with("/private/tmp/") or FileAccess.file_exists(out):
				push_error("Output requires a fresh /private/tmp/ file")
				quit(1)
				return
			var file := FileAccess.open(out, FileAccess.WRITE)
			file.store_string(JSON.stringify(report, "\t"))
			file.close()
	scene.free()
	quit(0 if report.errors.is_empty() else 1)


func _frames(count: int) -> void:
	for frame in range(count):
		await physics_frame
		await process_frame


func _landmarks(rest: bool) -> Dictionary:
	var result := {}
	for name in ["Hips", "Spine", "Spine2", "Neck", "Head", "LeftArm", "RightArm", "LeftHand", "RightHand", "LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]:
		var bone := skeleton.find_bone("mixamorig_" + name)
		if bone < 0: continue
		var transform := skeleton.get_bone_global_rest(bone) if rest else skeleton.get_bone_global_pose(bone)
		result[name] = _vec(player.to_local(skeleton.global_transform * transform.origin))
	return result


func _skin_bounds(rest: bool) -> Dictionary:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	var count := 0
	var meshes := 0
	var root_error := 0.0
	for mesh: MeshInstance3D in driver.model_root.find_children("*", "MeshInstance3D", true, false):
		if mesh.skin == null or mesh.mesh == null: continue
		meshes += 1
		root_error = maxf(root_error, mesh.global_position.distance_to(skeleton.global_position))
		var palette: Array[Transform3D] = []
		for bind in range(mesh.skin.get_bind_count()):
			var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind))
			if bone < 0: bone = mesh.skin.get_bind_bone(bind)
			var pose := skeleton.get_bone_global_rest(bone) if rest else skeleton.get_bone_global_pose(bone)
			palette.append(pose * mesh.skin.get_bind_pose(bind))
		for surface in range(mesh.mesh.get_surface_count()):
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influence_count := bones.size() / maxi(1, vertices.size())
			for vertex in range(vertices.size()):
				var point := Vector3.ZERO
				var weight_sum := 0.0
				for slot in range(influence_count):
					var index: int = vertex * influence_count + slot
					if weights[index] <= 0.0: continue
					point += (palette[bones[index]] * vertices[vertex]) * weights[index]
					weight_sum += weights[index]
				if weight_sum <= 0.0:
					report.errors.append("Unweighted vertex in " + String(mesh.name))
					continue
				point = player.to_local(skeleton.global_transform * point)
				low = low.min(point)
				high = high.max(point)
				count += 1
	return {"minimum": _vec(low), "maximum": _vec(high), "size": _vec(high-low),
		"vertices": count, "meshes": meshes, "mesh_skeleton_origin_difference_m": root_error,
		"method": "CPU weighted current bone pose times inverse bind; excludes unskinned weapon/gear"}


func _vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _transform(value: Transform3D) -> Dictionary:
	return {"origin": _vec(value.origin), "scale": _vec(value.basis.get_scale()),
		"basis_x": _vec(value.basis.x), "basis_y": _vec(value.basis.y), "basis_z": _vec(value.basis.z)}
