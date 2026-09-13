extends SceneTree

const Document := preload("res://scripts/maps/socom_map_document.gd")
const Commands := preload("res://scripts/maps/socom_map_command_service.gd")
const Runtime := preload("res://scripts/maps/socom_map_runtime.gd")
const PROP_IDS := ["relic_015", "relic_016", "relic_023", "relic_025", "relic_027", "relic_030", "relic_031", "relic_032"]
var errors: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var document := Document.load_path("res://config/maps/current_map.json")
	var library := Document.load_path("res://config/maps/relic_depot.json")
	var checked := 0
	for object: Dictionary in document.objects:
		var id := String(object.id)
		if id != "relic_001" and id not in PROP_IDS:
			_expect(not bool(object.properties.get("yard_finish", false)) and not bool(object.properties.get("yard_weathering", false)), "unselected object unchanged " + id)
			continue
		var key := "yard_weathering" if id == "relic_001" else "yard_finish"
		_expect(bool(object.properties.get(key, false)), "saved opt-in " + id)
		var disabled := Commands.apply(document, {"command": "set_object_properties", "id": id, "changes": {key: false}})
		_expect(bool(disabled.ok), "editor command accepted")
		var old: Dictionary = {}
		for candidate: Dictionary in disabled.document.objects:
			if candidate.id == id:
				old = candidate
		var original := Runtime.build_object(old, false)
		var original_state := _materials(original)
		var upgraded := Runtime.build_object(object, false)
		var preview := Runtime.build_object(object, true)
		_expect(_geometry(original) == _geometry(upgraded), "all geometry, transforms and collision unchanged " + id)
		_expect(_materials(original) == original_state, "cached source not mutated " + id)
		_expect(_materials(upgraded) == _materials(preview), "editor and runtime material parity " + id)
		if id == "relic_001":
			var mat := upgraded.get_node("Visual").material_override as StandardMaterial3D
			_expect(mat.next_pass is ShaderMaterial, "ground weathering consumed")
			_expect(is_equal_approx(float(mat.next_pass.get_shader_parameter("strength")), 0.45), "bounded ground strength")
			_expect(original.get_node("Visual").material_override.next_pass == null, "toggle off restores ground")
		else:
			for item: Dictionary in _materials(upgraded):
				_expect(item.shading == BaseMaterial3D.SHADING_MODE_PER_PIXEL, "lit imported material")
				_expect(item.filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC, "filtered imported material")
			_expect(not _materials(upgraded).is_empty(), "imported materials found")
		for candidate: Dictionary in library.objects:
			if candidate.id == id:
				_expect(candidate.properties == object.properties, "bundled library agrees " + id)
		original.free()
		upgraded.free()
		preview.free()
		checked += 1
	_expect(checked == 9, "one ground and eight props")
	var save_path := "/private/tmp/relic-yard-roundtrip.json"
	_expect(Document.save_path(document, save_path), "save succeeds")
	_expect(Document.load_path(save_path) == document, "saved contract survives roundtrip")
	_expect(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility", "renderer preserved")
	if "--editor" in OS.get_cmdline_user_args():
		# Isolate Map Lab's library writes from the user's own saved maps.
		Document.library_directory_override = "/private/tmp/relic-yard-editor-library"
		ProjectSettings.set_setting("socom/session/selected_map_document", document)
		change_scene_to_file("res://map_creation_lab.tscn")
		await scene_changed
		for frame in 3:
			await process_frame
		var lab := current_scene
		lab.selected_id = "relic_027"
		lab._refresh_inspector()
		_expect(lab.yard_finish_toggle.button_pressed, "editor reads saved flag")
		lab.yard_finish_toggle.button_pressed = false
		_expect(not bool(lab._selected_object().properties.yard_finish), "checkbox writes same contract")
		lab._undo()
		lab.selected_id = "relic_027"
		lab._refresh_inspector()
		_expect(lab.yard_finish_toggle.button_pressed, "undo restores saved flag")
		current_scene.queue_free()
		await process_frame
	print("RELIC_YARD_FINISH ", "PASS" if errors.is_empty() else "FAIL", " objects=", checked, " errors=", errors)
	quit(0 if errors.is_empty() else 1)

func _materials(node: Node) -> Array:
	var result: Array = []
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as BaseMaterial3D
			if material:
				result.append({"shading": material.shading_mode, "filter": material.texture_filter, "albedo": material.albedo_color, "roughness": material.roughness, "metallic": material.metallic, "texture": material.albedo_texture, "overlay": material.next_pass != null})
	return result

func _geometry(node: Node) -> Array:
	var result: Array = [String(node.name), node.get_class()]
	if node is Node3D:
		result.append(node.transform)
	if node is CollisionObject3D:
		result.append([node.collision_layer, node.collision_mask])
	if node is MeshInstance3D:
		result.append(node.mesh.get_faces())
	if node is CollisionShape3D:
		result.append(node.disabled)
		result.append(node.shape.get_class())
		if node.shape is BoxShape3D:
			result.append(node.shape.size)
		elif node.shape is ConcavePolygonShape3D:
			result.append(node.shape.get_faces())
	for child in node.get_children():
		result.append(_geometry(child))
	return result

func _expect(ok: bool, label: String) -> void:
	if not ok:
		errors.append(label)
		push_error(label)
