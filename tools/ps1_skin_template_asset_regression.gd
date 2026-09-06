extends SceneTree

## Asset-only proof. Does not load main.tscn, select a skin, or edit game profiles.
const BASE := "res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx"
const SAMPLE := "res://assets/characters/ps1_skin_template/ps1_skin_template_example.glb"
const REVIEW_SCALE := 62.0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var source := (load(BASE) as PackedScene).instantiate()
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var sample_path := ProjectSettings.globalize_path(SAMPLE)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--sample="):
			sample_path = argument.trim_prefix("--sample=")
	if document.append_from_file(sample_path, state) != OK:
		_expect(false, "sample GLB loads")
		source.free()
		_finish()
		return
	var sample := document.generate_scene(state)
	root.add_child(source)
	root.add_child(sample)
	await process_frame
	var original := _skeleton(source)
	var skeleton := _skeleton(sample)
	_expect(original != null and skeleton != null, "source and sample skeletons exist")
	if original == null or skeleton == null:
		source.queue_free()
		sample.queue_free()
		_finish()
		return
	_expect(skeleton.get_bone_count() == original.get_bone_count(), "no added or removed bones")
	var maximum_rest_distance := 0.0
	var maximum_rest_angle := 0.0
	for bone in original.get_bone_count():
		var name := original.get_bone_name(bone)
		var index := skeleton.find_bone(name)
		_expect(index >= 0, "retains native bone %s" % name)
		if index < 0:
			continue
		var source_parent := original.get_bone_parent(bone)
		var target_parent := skeleton.get_bone_parent(index)
		var source_parent_name := original.get_bone_name(source_parent) if source_parent >= 0 else ""
		var target_parent_name := skeleton.get_bone_name(target_parent) if target_parent >= 0 else ""
		_expect(source_parent_name == target_parent_name, "retains parent of %s" % name)
		var before := original.global_transform * original.get_bone_global_rest(bone)
		var after := skeleton.global_transform * skeleton.get_bone_global_rest(index)
		maximum_rest_distance = maxf(maximum_rest_distance, before.origin.distance_to(after.origin) * REVIEW_SCALE)
		maximum_rest_angle = maxf(maximum_rest_angle, rad_to_deg(before.basis.orthonormalized().get_rotation_quaternion().angle_to(after.basis.orthonormalized().get_rotation_quaternion())))
	_expect(maximum_rest_distance <= 0.001, "native bone positions remain within 1mm at game scale")
	_expect(maximum_rest_angle <= 0.1, "native bone rest rotations remain within 0.1 degree")
	var source_meshes := _meshes(source)
	var sample_meshes := _meshes(sample)
	var body: MeshInstance3D
	var helmet: MeshInstance3D
	var gear_triangles := 0
	for mesh in sample_meshes:
		if String(mesh.name).begins_with("BaseBody"):
			body = mesh
		else:
			gear_triangles += _triangles(mesh.mesh)
		if String(mesh.name).begins_with("Headgear"):
			helmet = mesh
		_validate_skin(mesh, skeleton)
	_expect(body != null, "one editable base body is exported")
	_expect(helmet != null, "modeled headgear is exported separately")
	_expect(gear_triangles > 0 and gear_triangles <= 1500, "gear changes geometry inside the 1500-triangle authoring budget")
	if body != null and not source_meshes.is_empty():
		var original_body := source_meshes[0]
		_expect(_triangles(body.mesh) == _triangles(original_body.mesh), "base triangle count is unchanged")
		# FBX and glTF may store identical rest geometry in different mesh-local
		# spaces. Compare the visible surface after each authored inverse bind.
		var original_points := _skinned_points(original_body, original)
		var candidate_points := _skinned_points(body, skeleton)
		var position_error := maxf(_point_error(original_points, candidate_points), _point_error(candidate_points, original_points)) * REVIEW_SCALE
		_expect(position_error <= 0.001, "base surface remains within 1mm of source at game scale")
		print("PS1_SKIN_TEMPLATE_GEOMETRY base_triangles=%d gear_triangles=%d position_error_m=%.6f rest_position_error_m=%.6f rest_angle_deg=%.6f" % [_triangles(body.mesh), gear_triangles, position_error, maximum_rest_distance, maximum_rest_angle])
	if helmet != null:
		_probe_gear(skeleton, helmet, "mixamorig_Head")
	for mesh in sample_meshes:
		if String(mesh.name).begins_with("ChestRig"):
			_probe_gear(skeleton, mesh, "mixamorig_Spine2")
	_expect(sample_meshes.size() >= 3, "base, headgear and chest modules remain separately editable")
	source.queue_free()
	sample.queue_free()
	await process_frame
	_finish()


func _validate_skin(mesh: MeshInstance3D, skeleton: Skeleton3D) -> void:
	_expect(mesh.skin != null and mesh.get_node_or_null(mesh.skeleton) == skeleton, "%s uses the same skeleton" % mesh.name)
	if mesh.skin == null:
		return
	var valid := true
	var maximum_influences := 0
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		if points.is_empty() or weights.is_empty() or bones.size() != weights.size():
			valid = false
			continue
		var stride: int = weights.size() / points.size()
		valid = valid and stride in [4, 8]
		for vertex in points.size():
			var total := 0.0
			var influences := 0
			for slot in stride:
				var offset := vertex * stride + slot
				var weight := weights[offset]
				total += weight
				if weight > 0.000001:
					influences += 1
					valid = valid and bones[offset] >= 0 and bones[offset] < mesh.skin.get_bind_count()
			maximum_influences = maxi(maximum_influences, influences)
			valid = valid and absf(total - 1.0) < 0.001 and points[vertex].is_finite()
	_expect(valid, "%s has finite vertices and normalized valid bone weights" % mesh.name)
	if String(mesh.name).begins_with("BaseBody"):
		_expect(maximum_influences >= 5, "base retains its original five-influence capacity without four-weight truncation")


func _probe_gear(skeleton: Skeleton3D, mesh: MeshInstance3D, name: String) -> void:
	var index := skeleton.find_bone(name)
	_expect(index >= 0, "%s attachment bone exists" % mesh.name)
	if index < 0:
		return
	var before := _skinned_points(mesh, skeleton)
	var saved := skeleton.get_bone_pose_rotation(index)
	skeleton.set_bone_pose_rotation(index, saved * Quaternion(Vector3.UP, deg_to_rad(20.0)))
	skeleton.force_update_all_bone_transforms()
	var after := _skinned_points(mesh, skeleton)
	skeleton.set_bone_pose_rotation(index, saved)
	skeleton.force_update_all_bone_transforms()
	# A centered symmetric helmet's centroid can stay still while it rotates.
	# Corresponding surface vertices, not its centroid, prove skin deformation.
	var squared_steps := 0.0
	for vertex in mini(before.size(), after.size()):
		squared_steps += before[vertex].distance_squared_to(after[vertex])
	var moved := sqrt(squared_steps / maxf(before.size(), 1.0)) * REVIEW_SCALE
	_expect(is_finite(moved) and moved > 0.001 and moved < 0.5, "%s follows %s pose through skin weights" % [mesh.name, name])
	print("PS1_SKIN_GEAR_PROBE mesh=%s bone=%s rms_vertex_step_m=%.6f" % [mesh.name, name, moved])


func _skinned_points(mesh: MeshInstance3D, skeleton: Skeleton3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var stride: int = weights.size() / points.size()
		for vertex in points.size():
			var point := Vector3.ZERO
			for slot in stride:
				var offset := vertex * stride + slot
				if weights[offset] <= 0.000001:
					continue
				var bind := bones[offset]
				var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind))
				if bone < 0:
					bone = mesh.skin.get_bind_bone(bind)
				point += (skeleton.global_transform * skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) * points[vertex]) * weights[offset]
			result.append(point)
	return result


func _point_error(first: PackedVector3Array, second: PackedVector3Array) -> float:
	var error := 0.0
	for point in first:
		var closest := INF
		for candidate in second:
			closest = minf(closest, point.distance_to(candidate))
		error = maxf(error, closest)
	return error


func _triangles(mesh: Mesh) -> int:
	return mesh.get_faces().size() / 3


func _skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _skeleton(child)
		if found != null:
			return found
	return null


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_meshes(child))
	return result


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("PS1_SKIN_TEMPLATE FAIL " + message)


func _finish() -> void:
	print("PS1_SKIN_TEMPLATE_ASSET_REGRESSION %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
