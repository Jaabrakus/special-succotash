extends SceneTree

func _initialize() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file("res://assets/characters/canonical_military_variant/canonical_military_variant.glb", state)
	if error != OK:
		push_error("CANONICAL_MILITARY_IMPORT_FAILED %s" % error)
		quit(1)
		return
	var scene := document.generate_scene(state)
	if scene == null:
		quit(1)
		return
	root.add_child(scene)
	var skeletons := scene.find_children("*", "Skeleton3D", true, false)
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	var bones := (skeletons[0] as Skeleton3D).get_bone_count() if skeletons.size() == 1 else 0
	var surfaces := 0
	var triangles := 0
	var max_influences := 0
	var material_values: Dictionary = {}
	for node in meshes:
		var mesh := node as MeshInstance3D
		for index in mesh.mesh.get_surface_count():
			surfaces += 1
			var arrays := mesh.mesh.surface_get_arrays(index)
			triangles += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			var vertex_count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var slots := (arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size() / vertex_count
			max_influences = maxi(max_influences, slots)
			var material := mesh.get_active_material(index) as BaseMaterial3D
			material_values[material.resource_name] = {
				"color": [material.albedo_color.r, material.albedo_color.g, material.albedo_color.b],
				"source_texture_present": material.albedo_texture != null
			}
	var palette := material_values.get("Military_MutedOlive_Fatigue", {}) as Dictionary
	var tint: Array = palette.get("color", [])
	# glTF baseColorFactor is linear; Godot exposes albedo_color in sRGB.
	var expected := Color(0.85, 1.0, 0.38).linear_to_srgb()
	var tint_ok := tint.size() == 3 and absf(float(tint[0]) - expected.r) < 0.005 and absf(float(tint[2]) - expected.b) < 0.005
	var passed := bones == 41 and meshes.size() == 1 and surfaces == 3 and triangles == 680 and max_influences == 8 and tint_ok and bool(palette.get("source_texture_present", false))
	print("CANONICAL_MILITARY_GODOT_IMPORT ", JSON.stringify({"pass": passed,
		"native_bones": bones, "mesh_nodes": meshes.size(), "surfaces": surfaces,
		"triangles": triangles, "skin_influence_slots": max_influences,
		"materials": material_values,
		"scope": "Same-mesh material candidate import only; no runtime swap or pose claim"}))
	scene.queue_free()
	quit(0 if passed else 1)
