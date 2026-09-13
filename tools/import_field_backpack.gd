extends SceneTree

## Run explicitly after replacing the original export; no runtime GLB parsing.
func _init() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var err := document.append_from_file("res://assets/props/agls_field_backpack/source.glb", state)
	if err != OK:
		push_error("Backpack import failed: %s" % err)
		quit(1)
		return
	var source := document.generate_scene(state)
	var bounds := _bounds(source, Transform3D.IDENTITY)
	print("FIELD_BACKPACK_SOURCE bounds=", bounds)
	var wrapper := Node3D.new()
	wrapper.name = "AGLSFieldBackpack"
	wrapper.add_child(source)
	var factor := 0.52 / bounds.size.y
	source.scale *= factor
	source.position -= bounds.get_center() * factor
	_own(wrapper, wrapper)
	var packed := PackedScene.new()
	err = packed.pack(wrapper)
	if err == OK:
		err = ResourceSaver.save(packed, "res://assets/props/agls_field_backpack/backpack.scn", ResourceSaver.FLAG_COMPRESS)
	print("FIELD_BACKPACK_IMPORT result=%d normalized_size=%s" % [err, bounds.size * factor])
	wrapper.free()
	quit(0 if err == OK else 1)

func _bounds(node: Node, parent_transform: Transform3D) -> AABB:
	var transform := parent_transform
	if node is Node3D:
		transform *= (node as Node3D).transform
	var result := AABB()
	if node is MeshInstance3D:
		result = transform * (node as MeshInstance3D).get_aabb()
	for child in node.get_children():
		var box := _bounds(child, transform)
		if box.size != Vector3.ZERO:
			result = box if result.size == Vector3.ZERO else result.merge(box)
	return result

func _own(node: Node, root_node: Node) -> void:
	for child in node.get_children():
		child.owner = root_node
		_own(child, root_node)
