extends SceneTree

## Observer only; raw GLB import does not modify the playable game or assets.
const DEFAULT_MANIFEST := "res://assets/weapons/socom2_source/v2/manifest.json"
const REPRESENTATIVES := ["a_mark23", "m4Acarbine", "ak47"]
const BOUNDS_TOLERANCE_M := 0.00001
var failures: Array[String] = []
var captures: Array = []
var prefix := ""
var manifest_path := DEFAULT_MANIFEST
var capture_enabled := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--capture": capture_enabled = true
		elif argument.begins_with("--manifest="): manifest_path = argument.trim_prefix("--manifest=")
		elif argument.begins_with("--output-prefix="): prefix = argument.trim_prefix("--output-prefix=")
		else: _check(false, "Unknown argument " + argument)
	_check(FileAccess.file_exists(manifest_path), "Extraction manifest must exist: " + manifest_path)
	if capture_enabled:
		_check(DisplayServer.get_name() != "headless", "Capture requires a rendering display; numerical checks support headless")
		_check(not prefix.is_empty(), "Capture requires a fresh output prefix")
	if not prefix.is_empty():
		_check(prefix == prefix.simplify_path() and (prefix.begins_with("/private/tmp/") or prefix.begins_with("res://art_source/")), "Output prefix must be canonical and restricted to proof directories")
		_check(DirAccess.dir_exists_absolute(prefix.get_base_dir()), "Output parent must already exist")
		_check(not FileAccess.file_exists(prefix + ".json"), "Refusing existing output " + prefix + ".json")
		for model: String in REPRESENTATIVES:
			for angle in 2:
				_check(not FileAccess.file_exists(_capture_path(model, angle)), "Refusing existing capture " + _capture_path(model, angle))
	if not failures.is_empty():
		_finish({})
		return
	var manifest_sha := FileAccess.get_sha256(manifest_path)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	_check(manifest.get("schema_version") == 1 and manifest.get("models") is Array, "Supported manifest schema")
	if not failures.is_empty():
		_finish({})
		return
	var rows: Array = []
	var models: Dictionary = {}
	var vertex_total := 0
	var triangle_total := 0
	for model: Dictionary in manifest.models:
		models[str(model.name)] = model
		for part: Dictionary in model.parts:
			var path := _part_path(part)
			_check(FileAccess.file_exists(path), "Part file exists " + path)
			if not FileAccess.file_exists(path): continue
			_check(FileAccess.get_sha256(path) == str(part.sha256), "Part checksum " + path)
			var loaded := _load_part(path)
			if loaded.is_empty(): continue
			var instance: Node = loaded.scene
			var state: GLTFState = loaded.state
			var imported := _geometry(instance)
			var expected_vertices := int(part.get("exported_vertex_count", part.vertices))
			var expected_indices := int(part.get("exported_index_count", int(part.triangles) * 3))
			var gltf_counts := _gltf_counts(state)
			var label := str(model.name) + "/" + str(part.name)
			_check(imported.finite, "Finite vertices/normals/UVs/transforms " + label)
			_check(imported.valid_indices, "Triangle indices in range " + label)
			_check(gltf_counts.vertices == expected_vertices and gltf_counts.indices == expected_indices, "GLB accessors match decoder counts " + label)
			_check(imported.vertices == expected_vertices and imported.indices == expected_indices, "Godot mesh counts match decoder " + label)
			_check(imported.surfaces == gltf_counts.primitives, "Godot surfaces preserve material batches " + label)
			var material_count := state.get_materials().size()
			_check(material_count == int(part.get("material_count", state.json.get("materials", []).size())), "Imported material count " + label)
			_check(material_count == imported.surfaces and imported.material_slots_filled, "All part material slots bound " + label)
			_check(state.get_images().size() == material_count, "Embedded texture image count " + label)
			var bounds: Dictionary = part.decoded_model_bounds_meters
			var expected_min := _vector(bounds.min)
			var expected_max := _vector(bounds.max)
			var actual_bounds: AABB = imported.bounds
			var bound_error := maxf(_max_component_abs(actual_bounds.position - expected_min), _max_component_abs(actual_bounds.end - expected_max))
			_check(imported.vertices > 0 and bound_error <= BOUNDS_TOLERANCE_M, "Baked model-space metre bounds " + label)
			rows.append({"model": str(model.name), "part": str(part.name), "file": path,
				"sha256": FileAccess.get_sha256(path), "source_node": part.get("source_node"), "visual_word": part.get("visual_word"),
				"vertices": imported.vertices, "indices": imported.indices, "triangles": int(imported.indices) / 3,
				"materials": material_count, "surfaces": imported.surfaces,
				"gltf_accessor_counts": gltf_counts, "bounds_min_m": _array(actual_bounds.position),
				"bounds_max_m": _array(actual_bounds.end), "maximum_bound_error_m": bound_error})
			vertex_total += imported.vertices
			triangle_total += int(imported.indices) / 3
			instance.free()
	_check(models.size() == 59, "All 59 source weapon model entries present")
	_check(FileAccess.get_sha256(manifest_path) == manifest_sha, "Manifest unchanged during proof")
	if capture_enabled and failures.is_empty():
		root.set_disable_input(true)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		root.size = Vector2i(1200, 800)
		for name: String in REPRESENTATIVES:
			_check(models.has(name), "Representative model exists " + name)
			if models.has(name): await _capture_model(models[name])
	var report := {"schema_version": 1, "manifest": manifest_path, "manifest_sha256": manifest_sha,
		"engine": Engine.get_version_info(), "models": models.size(), "parts": rows.size(),
		"vertices": vertex_total, "triangles": triangle_total, "part_results": rows, "captures": captures,
		"status": "Godot import proof, not original PS2 rendering or runtime mount parity", "failures": failures}
	if not prefix.is_empty():
		_check(not FileAccess.file_exists(prefix + ".json"), "Report path remained unused")
		if failures.is_empty():
			var out := FileAccess.open(prefix + ".json", FileAccess.WRITE)
			_check(out != null, "Open new proof report")
			if out != null:
				out.store_string(JSON.stringify(report, "\t") + "\n")
				out.close()
	_finish({"models": models.size(), "parts": rows.size(), "vertices": vertex_total, "triangles": triangle_total, "captures": captures.size()})


func _part_path(part: Dictionary) -> String:
	var file := str(part.get("file", ""))
	_check(file == file.get_file() and file.ends_with(".glb"), "Part is a local GLB basename")
	return manifest_path.get_base_dir().path_join("models").path_join(file)


func _load_part(path: String) -> Dictionary:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	state.create_animations = false
	# Explicit in-memory image handling also keeps editor invocations read-only.
	state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
	# Keep import compression out of a quantitative geometry comparison.
	var error := document.append_from_file(path, state, GLTFDocument.IMPORT_FLAG_FORCE_DISABLE_MESH_COMPRESSION)
	_check(error == OK, "GLTFDocument import " + path + " code=" + str(error))
	if error != OK: return {}
	var scene := document.generate_scene(state)
	_check(scene != null, "GLTF scene generated " + path)
	return {"scene": scene, "state": state} if scene != null else {}


func _geometry(node: Node, parent_transform: Transform3D = Transform3D.IDENTITY) -> Dictionary:
	var frame := parent_transform * ((node as Node3D).transform if node is Node3D else Transform3D.IDENTITY)
	var result := {"vertices": 0, "indices": 0, "surfaces": 0, "finite": frame.is_finite(),
		"valid_indices": true, "material_slots_filled": true, "bounds": AABB()}
	if node is MeshInstance3D and node.mesh != null:
		var mesh: Mesh = node.mesh
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			result.surfaces += 1
			result.material_slots_filled = result.material_slots_filled and mesh.surface_get_material(surface) != null
			result.valid_indices = result.valid_indices and mesh.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES and indices.size() % 3 == 0
			for index in indices: result.valid_indices = result.valid_indices and index >= 0 and index < vertices.size()
			for vertex in vertices:
				var point := frame * vertex
				result.finite = result.finite and point.is_finite()
				result.bounds = AABB(point, Vector3.ZERO) if result.vertices == 0 else (result.bounds as AABB).expand(point)
				result.vertices += 1
			result.indices += indices.size()
			for channel in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV]:
				if arrays[channel] != null:
					for value in arrays[channel]: result.finite = result.finite and value.is_finite()
	for child: Node in node.get_children():
		var nested := _geometry(child, frame)
		if nested.vertices > 0:
			result.bounds = nested.bounds if result.vertices == 0 else (result.bounds as AABB).merge(nested.bounds)
		result.vertices += nested.vertices
		result.indices += nested.indices
		result.surfaces += nested.surfaces
		result.finite = result.finite and nested.finite
		result.valid_indices = result.valid_indices and nested.valid_indices
		result.material_slots_filled = result.material_slots_filled and nested.material_slots_filled
	return result


func _gltf_counts(state: GLTFState) -> Dictionary:
	var result := {"vertices": 0, "indices": 0, "primitives": 0}
	for mesh: Dictionary in state.json.get("meshes", []):
		for primitive: Dictionary in mesh.primitives:
			result.vertices += int(state.json.accessors[int(primitive.attributes.POSITION)].count)
			result.indices += int(state.json.accessors[int(primitive.indices)].count)
			result.primitives += 1
	return result


func _capture_model(model: Dictionary) -> void:
	# Select an actual source 'high' node when present, otherwise the first
	# manifest part with raw high-detail-correlated word 0x100. Do not stack LODs.
	var selected: Dictionary = {}
	for part: Dictionary in model.parts:
		if str(part.get("source_node", "")).to_lower() == "high" and int(part.get("visual_word", -1)) == 0x100:
			selected = part
			break
	if selected.is_empty():
		for part: Dictionary in model.parts:
			if int(part.get("visual_word", -1)) == 0x100:
				selected = part
				break
	_check(not selected.is_empty(), "Explicit high-detail representative available " + str(model.name))
	if selected.is_empty(): return
	var loaded := _load_part(_part_path(selected))
	if loaded.is_empty(): return
	var stage := Node3D.new()
	root.add_child(stage)
	var model_node: Node = loaded.scene
	stage.add_child(model_node)
	var data := _geometry(model_node)
	var bounds: AABB = data.bounds
	var center := bounds.get_center()
	var extent := maxf(bounds.size.length(), 0.05)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.15, 0.18)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.75
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -25, 0)
	sun.light_energy = 1.0
	stage.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = extent * 1.1
	camera.near = maxf(0.001, extent * 0.001)
	camera.far = extent * 20
	stage.add_child(camera)
	camera.make_current()
	var major_x := bounds.size.x >= bounds.size.z
	for angle in 2:
		var sign := -1.0 if angle == 1 else 1.0
		var direction := Vector3(0.35, 0.35, sign) if major_x else Vector3(sign, 0.35, 0.35)
		camera.position = center + direction.normalized() * extent * 3.0
		camera.look_at(center)
		for frame in 4: await process_frame
		await RenderingServer.frame_post_draw
		var path := _capture_path(str(model.name), angle)
		_check(not FileAccess.file_exists(path), "Capture destination remains unused")
		if FileAccess.file_exists(path): continue
		var image := root.get_texture().get_image()
		_check(not image.is_empty(), "Rendered image available")
		if not image.is_empty():
			_check(image.save_png(path) == OK, "Save capture " + path)
			captures.append({"model": model.name, "part": selected.name, "visual_word": selected.visual_word,
				"file": ProjectSettings.globalize_path(path), "camera_position": _array(camera.position), "camera_target": _array(center)})
	stage.free()


func _capture_path(model: String, angle: int) -> String:
	return prefix + "-" + model + "-angle" + str(angle + 1) + ".png"


func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _max_component_abs(value: Vector3) -> float:
	return maxf(absf(value.x), maxf(absf(value.y), absf(value.z)))


func _check(ok: bool, reason: String) -> void:
	if not ok and not reason in failures: failures.append(reason)


func _finish(summary: Dictionary) -> void:
	print("SOURCE_WEAPON_ASSET_PROOF ", "PASS " if failures.is_empty() else "FAIL ", JSON.stringify(summary), " failures=", failures)
	quit(0 if failures.is_empty() else 1)
