class_name SocomMapAssetLibrary
extends RefCounted

## Safe boundary for community-authored map geometry. GLB is intentionally the
## first supported format because it is self-contained: mesh, materials, and
## textures travel together without executing project scripts.

const USER_ASSET_DIRECTORY := "user://map_assets"
const MAX_ASSET_BYTES := 128 * 1024 * 1024
const MAX_MESH_INSTANCES := 512
const MAX_VERTICES := 1_000_000


static func import_glb(source_path: String) -> Dictionary:
	if source_path.get_extension().to_lower() != "glb":
		return {"ok": false, "message": "Choose a self-contained .glb file."}
	if not FileAccess.file_exists(source_path):
		return {"ok": false, "message": "Asset file does not exist."}
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return {"ok": false, "message": "Asset file could not be opened."}
	var byte_count := source.get_length()
	if byte_count <= 0 or byte_count > MAX_ASSET_BYTES:
		return {"ok": false, "message": "GLB must be between 1 byte and 128 MB."}
	var bytes := source.get_buffer(byte_count)
	source.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(USER_ASSET_DIRECTORY))
	var safe_stem := _safe_filename(source_path.get_file().get_basename())
	var target_path := "%s/%s.glb" % [USER_ASSET_DIRECTORY, safe_stem]
	var suffix := 2
	while FileAccess.file_exists(target_path):
		target_path = "%s/%s_%d.glb" % [USER_ASSET_DIRECTORY, safe_stem, suffix]
		suffix += 1
	var target := FileAccess.open(target_path, FileAccess.WRITE)
	if target == null:
		return {"ok": false, "message": "Could not copy the GLB into the community asset library."}
	target.store_buffer(bytes)
	target.close()
	var validation := instantiate_asset(target_path)
	if not bool(validation.get("ok", false)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(target_path))
		return validation
	var preview: Node = validation.get("scene")
	if preview != null:
		preview.free()
	return {"ok": true, "message": "Imported %s" % source_path.get_file(), "path": target_path, "label": _label_from_path(target_path)}


static func list_assets() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var directory := DirAccess.open(USER_ASSET_DIRECTORY)
	if directory == null:
		return entries
	for filename in directory.get_files():
		if filename.get_extension().to_lower() != "glb":
			continue
		var path := "%s/%s" % [USER_ASSET_DIRECTORY, filename]
		entries.append({"path": path, "label": _label_from_path(path)})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["label"]).naturalnocasecmp_to(String(b["label"])) < 0)
	return entries


static func is_allowed_asset_path(path: String) -> bool:
	if path.get_extension().to_lower() != "glb":
		return false
	return path.begins_with("res://") or path.begins_with("user://map_assets/")


static func asset_exists(path: String) -> bool:
	if not is_allowed_asset_path(path):
		return false
	return ResourceLoader.exists(path) if path.begins_with("res://") else FileAccess.file_exists(path)


static func instantiate_asset(path: String) -> Dictionary:
	if not asset_exists(path):
		return {"ok": false, "message": "Imported asset is missing or outside the safe library."}
	var scene: Node3D
	if path.begins_with("res://"):
		var resource := load(path)
		if resource is PackedScene:
			scene = (resource as PackedScene).instantiate() as Node3D
	else:
		var gltf := GLTFDocument.new()
		var state := GLTFState.new()
		var error := gltf.append_from_file(path, state)
		if error != OK:
			return {"ok": false, "message": "Godot could not read this GLB (%s)." % error_string(error)}
		scene = gltf.generate_scene(state) as Node3D
	if scene == null:
		return {"ok": false, "message": "GLB did not contain a usable 3D scene."}
	_strip_unsafe_or_editor_nodes(scene)
	var metrics := _scene_metrics(scene)
	if int(metrics["mesh_count"]) == 0:
		scene.free()
		return {"ok": false, "message": "GLB contains no renderable meshes."}
	if int(metrics["mesh_count"]) > MAX_MESH_INSTANCES or int(metrics["vertex_count"]) > MAX_VERTICES:
		scene.free()
		return {"ok": false, "message": "Asset is too complex. Limit: 512 mesh pieces and 1,000,000 vertices."}
	return {"ok": true, "scene": scene, "mesh_count": metrics["mesh_count"], "vertex_count": metrics["vertex_count"]}


static func _strip_unsafe_or_editor_nodes(root: Node) -> void:
	for child in root.get_children():
		if child is Camera3D or child is Light3D or child is AudioStreamPlayer3D:
			root.remove_child(child)
			child.free()
		else:
			_strip_unsafe_or_editor_nodes(child)


static func _scene_metrics(root: Node) -> Dictionary:
	var mesh_count := 0
	var vertex_count := 0
	var nodes: Array[Node] = [root]
	while not nodes.is_empty():
		var node: Node = nodes.pop_back()
		if node is MeshInstance3D:
			var mesh: Mesh = (node as MeshInstance3D).mesh
			if mesh != null:
				mesh_count += 1
				for surface_index in mesh.get_surface_count():
					var arrays: Array = mesh.surface_get_arrays(surface_index)
					if not arrays.is_empty() and arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
						vertex_count += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for child in node.get_children():
			nodes.append(child)
	return {"mesh_count": mesh_count, "vertex_count": vertex_count}


static func _safe_filename(value: String) -> String:
	var safe := ""
	for character in value.to_lower():
		safe += character if character.is_valid_identifier() or character.is_valid_int() or character in ["-", "_"] else "_"
	while "__" in safe:
		safe = safe.replace("__", "_")
	safe = safe.trim_prefix("_").trim_suffix("_")
	return safe if not safe.is_empty() else "community_asset"


static func _label_from_path(path: String) -> String:
	return path.get_file().get_basename().replace("_", " ").capitalize()
