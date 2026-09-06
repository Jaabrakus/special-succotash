extends SceneTree

## Proves the Blender output keeps the canonical body/rest rig and is the mesh
## consumed by main.tscn. Presentation geometry must not acquire gameplay power.

const SOURCE := "res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx"
const CANDIDATE := "res://assets/characters/socom2_tan_operator/socom2_tan_operator.glb"
const PLAYER_SCENE := "res://scenes/player/operator_player.tscn"
const REVIEW_SCALE := 62.0

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var source_packed := load(SOURCE) as PackedScene
	var candidate_packed := load(CANDIDATE) as PackedScene
	_expect(source_packed != null, "canonical source FBX loads")
	_expect(candidate_packed != null, "SOCOM 2 tan GLB loads")
	if source_packed == null or candidate_packed == null:
		_finish()
		return
	var source := source_packed.instantiate()
	var candidate := candidate_packed.instantiate()
	root.add_child(source)
	root.add_child(candidate)
	await process_frame

	var source_skeleton := _skeleton(source)
	var candidate_skeleton := _skeleton(candidate)
	_expect(source_skeleton != null and candidate_skeleton != null, "both assets have one native Skeleton3D")
	if source_skeleton == null or candidate_skeleton == null:
		source.queue_free()
		candidate.queue_free()
		_finish()
		return
	_expect(candidate_skeleton.get_bone_count() == 41, "candidate exports the native 41-bone rig")
	_expect(candidate_skeleton.get_bone_count() == source_skeleton.get_bone_count(), "no bones are added or removed")
	var source_skeleton_scale := source_skeleton.global_basis.get_scale()
	var candidate_skeleton_scale := candidate_skeleton.global_basis.get_scale()
	print(
		"SOCOM2_TAN_NATIVE_SCALE source=%s candidate=%s motion_source=%s motion_candidate=%s"
		% [
			source_skeleton_scale,
			candidate_skeleton_scale,
			source_skeleton.motion_scale,
			candidate_skeleton.motion_scale,
		]
	)
	print(
		"SOCOM2_TAN_SKELETON_TRANSFORM source=%s candidate=%s"
		% [source_skeleton.global_transform, candidate_skeleton.global_transform]
	)
	_expect(
		source_skeleton_scale.distance_to(candidate_skeleton_scale) <= 0.00001,
		"candidate preserves the source skeleton object scale"
	)
	var maximum_rest_distance := 0.0
	var maximum_rest_angle := 0.0
	var maximum_local_rest_distance := 0.0
	var maximum_local_rest_angle := 0.0
	for source_index in source_skeleton.get_bone_count():
		var bone_name := source_skeleton.get_bone_name(source_index)
		var candidate_index := candidate_skeleton.find_bone(bone_name)
		_expect(candidate_index >= 0, "retains native bone %s" % bone_name)
		if candidate_index < 0:
			continue
		var source_parent := source_skeleton.get_bone_parent(source_index)
		var candidate_parent := candidate_skeleton.get_bone_parent(candidate_index)
		var source_parent_name := source_skeleton.get_bone_name(source_parent) if source_parent >= 0 else ""
		var candidate_parent_name := candidate_skeleton.get_bone_name(candidate_parent) if candidate_parent >= 0 else ""
		_expect(source_parent_name == candidate_parent_name, "retains parent of %s" % bone_name)
		var source_rest := source_skeleton.global_transform * source_skeleton.get_bone_global_rest(source_index)
		var candidate_rest := candidate_skeleton.global_transform * candidate_skeleton.get_bone_global_rest(candidate_index)
		var source_local_rest := source_skeleton.get_bone_rest(source_index)
		var candidate_local_rest := candidate_skeleton.get_bone_rest(candidate_index)
		maximum_rest_distance = maxf(
			maximum_rest_distance,
			source_rest.origin.distance_to(candidate_rest.origin) * REVIEW_SCALE
		)
		maximum_rest_angle = maxf(
			maximum_rest_angle,
			rad_to_deg(
				source_rest.basis.orthonormalized().get_rotation_quaternion().angle_to(
					candidate_rest.basis.orthonormalized().get_rotation_quaternion()
				)
			)
		)
		maximum_local_rest_distance = maxf(
			maximum_local_rest_distance,
			source_local_rest.origin.distance_to(candidate_local_rest.origin) * REVIEW_SCALE
		)
		maximum_local_rest_angle = maxf(
			maximum_local_rest_angle,
			rad_to_deg(
				source_local_rest.basis.orthonormalized().get_rotation_quaternion().angle_to(
					candidate_local_rest.basis.orthonormalized().get_rotation_quaternion()
				)
			)
		)
	_expect(maximum_rest_distance <= 0.001, "native bone positions remain within 1 mm")
	_expect(maximum_rest_angle <= 0.1, "native bone rotations remain within 0.1 degree")
	_expect(maximum_local_rest_distance <= 0.001, "native local bone positions remain within 1 mm")
	_expect(maximum_local_rest_angle <= 0.1, "native local bone rotations remain within 0.1 degree")

	var source_meshes := _meshes(source)
	var candidate_meshes := _meshes(candidate)
	var body := _mesh_named(candidate_meshes, "BaseBody")
	var headgear := _mesh_named(candidate_meshes, "Headgear")
	var rear_armor := _mesh_named(candidate_meshes, "RearArmorAndWebbing")
	var belt_kit := _mesh_named(candidate_meshes, "BeltKitAndHipPouch")
	_expect(body != null, "candidate contains BaseBody")
	_expect(headgear != null, "candidate contains bone-bound Headgear")
	_expect(rear_armor != null, "candidate contains bone-bound rear armor and webbing")
	_expect(belt_kit != null, "candidate contains bone-bound belt kit and hip pouch")
	var gear_triangles := 0
	for mesh in candidate_meshes:
		_validate_skin(mesh, candidate_skeleton)
		if mesh != body:
			gear_triangles += _triangles(mesh.mesh)
	_expect(gear_triangles == 1176, "gear triangle count matches the reviewed Blender build")
	_expect(gear_triangles <= 2400, "gear stays inside the low-poly budget")
	if body != null and not source_meshes.is_empty():
		var source_body := source_meshes[0]
		_expect(_triangles(source_body.mesh) == 680, "canonical source body remains 680 triangles")
		_expect(_triangles(body.mesh) == 680, "candidate body remains 680 triangles")
		var source_points := _skinned_points(source_body, source_skeleton)
		var candidate_points := _skinned_points(body, candidate_skeleton)
		var surface_error := maxf(
			_point_error(source_points, candidate_points),
			_point_error(candidate_points, source_points)
		) * REVIEW_SCALE
		_expect(surface_error <= 0.001, "base surface remains within 1 mm of source")
		_expect(_has_material(body, "SOCOM2_TanFatigue"), "body imports the authored tan fatigue material")
		print(
			"SOCOM2_TAN_ASSET base_triangles=680 gear_triangles=%d surface_error_m=%.6f rest_error_m=%.6f rest_angle_deg=%.6f"
			% [gear_triangles, surface_error, maximum_rest_distance, maximum_rest_angle]
		)
		print(
			"SOCOM2_TAN_LOCAL_REST position_error_m=%.6f angle_error_deg=%.6f"
			% [maximum_local_rest_distance, maximum_local_rest_angle]
		)
	if headgear != null:
		_probe_gear(candidate_skeleton, headgear, "mixamorig_Head")
	if rear_armor != null:
		_probe_gear(candidate_skeleton, rear_armor, "mixamorig_Spine2")
	if belt_kit != null:
		_probe_gear(candidate_skeleton, belt_kit, "mixamorig_Hips")

	_validate_runtime_contract()
	source.queue_free()
	candidate.queue_free()
	await process_frame
	_finish()


func _validate_runtime_contract() -> void:
	var player_source := FileAccess.get_file_as_string(PLAYER_SCENE)
	var runtime_source := FileAccess.get_file_as_string("res://scripts/player/operator_asset_runtime.gd")
	var warmup_source := FileAccess.get_file_as_string("res://scripts/runtime/playable_resource_warmup.gd")
	var export_source := FileAccess.get_file_as_string("res://export_presets.cfg")
	_expect(player_source.contains(SOURCE), "canonical player reverted to original blue/green source")
	_expect(runtime_source.contains(SOURCE), "asset runtime fallback uses original source")
	_expect(not runtime_source.contains("_apply_texture(model_root)"), "runtime preserves authored Blender materials")
	_expect(warmup_source.contains(SOURCE), "playable warmup uses original source")
	_expect(export_source.contains("assets/characters/socom2_tan_operator/*"), "restricted web export packages the tan operator")
	var packed := load(PLAYER_SCENE) as PackedScene
	_expect(packed != null, "canonical operator player scene loads")
	if packed == null:
		return
	var player := packed.instantiate()
	_expect(player is CharacterBody3D, "CharacterBody3D remains movement and collision owner")
	_expect(player.get_node_or_null("CollisionShape3D") is CollisionShape3D, "canonical collision node remains present")
	var model := player.get_node_or_null("Mannequin/ProductionAnimation/TrooperModel")
	_expect(model is Node3D, "canonical presentation node contains original operator")
	if model != null:
		var meshes := _meshes(model)
		_expect(_mesh_named(meshes, "RearArmorAndWebbing") == null, "tan gear retained as asset only, not active")
		var skeleton := _skeleton(model)
		if skeleton != null:
			print("SOCOM2_TAN_RUNTIME_SCALE model=%s skeleton_local=%s" % [model.scale, skeleton.scale])
	player.free()


func _validate_skin(mesh: MeshInstance3D, skeleton: Skeleton3D) -> void:
	_expect(mesh.skin != null and mesh.get_node_or_null(mesh.skeleton) == skeleton, "%s uses the native skeleton" % mesh.name)
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
	_expect(valid, "%s has finite vertices and normalized valid weights" % mesh.name)
	if String(mesh.name).begins_with("BaseBody"):
		_expect(maximum_influences >= 5, "base retains five-influence skin capacity")


func _probe_gear(skeleton: Skeleton3D, mesh: MeshInstance3D, bone_name: String) -> void:
	var bone := skeleton.find_bone(bone_name)
	_expect(bone >= 0, "%s attachment bone exists" % mesh.name)
	if bone < 0:
		return
	var before := _skinned_points(mesh, skeleton)
	var saved := skeleton.get_bone_pose_rotation(bone)
	skeleton.set_bone_pose_rotation(bone, saved * Quaternion(Vector3.UP, deg_to_rad(20.0)))
	skeleton.force_update_all_bone_transforms()
	var after := _skinned_points(mesh, skeleton)
	skeleton.set_bone_pose_rotation(bone, saved)
	skeleton.force_update_all_bone_transforms()
	var squared_steps := 0.0
	for vertex in mini(before.size(), after.size()):
		squared_steps += before[vertex].distance_squared_to(after[vertex])
	var moved := sqrt(squared_steps / maxf(before.size(), 1.0)) * REVIEW_SCALE
	_expect(is_finite(moved) and moved > 0.001 and moved < 0.5, "%s follows %s" % [mesh.name, bone_name])
	print("SOCOM2_TAN_GEAR_PROBE mesh=%s bone=%s rms_step_m=%.6f" % [mesh.name, bone_name, moved])


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
				point += (
					skeleton.global_transform
					* skeleton.get_bone_global_pose(bone)
					* mesh.skin.get_bind_pose(bind)
					* points[vertex]
				) * weights[offset]
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


func _has_material(mesh: MeshInstance3D, expected: String) -> bool:
	for surface in mesh.mesh.get_surface_count():
		var material := mesh.mesh.surface_get_material(surface)
		if material != null and String(material.resource_name).contains(expected):
			return true
	return false


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


func _mesh_named(meshes: Array[MeshInstance3D], prefix: String) -> MeshInstance3D:
	for mesh in meshes:
		if String(mesh.name).begins_with(prefix):
			return mesh
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("SOCOM2_TAN_OPERATOR FAIL " + message)


func _finish() -> void:
	print("SOCOM2_TAN_OPERATOR_REGRESSION %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
