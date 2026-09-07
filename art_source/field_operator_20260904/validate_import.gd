extends SceneTree

func _initialize() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var path := "res://assets/characters/field_operator_20260904/field_operator_aim_ready.glb"
	var error := document.append_from_file(path, state)
	if error != OK:
		push_error("FIELD_OPERATOR_IMPORT_FAILED %s" % error)
		quit(1)
		return
	var scene := document.generate_scene(state)
	if scene == null:
		push_error("FIELD_OPERATOR_SCENE_FAILED")
		quit(1)
		return
	root.add_child(scene)
	var skeletons := scene.find_children("*", "Skeleton3D", true, false)
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	var animations := scene.find_children("*", "AnimationPlayer", true, false)
	var skin_count := 0
	var surface_count := 0
	var vertex_palette_imported := false
	for node in meshes:
		var mesh := node as MeshInstance3D
		if mesh.skin != null:
			skin_count += 1
		if mesh.mesh != null:
			surface_count += mesh.mesh.get_surface_count()
			if mesh.name == "FieldOperator_OriginalSkinnedMesh":
				# glTF COLOR_0 is present. The direct 4.7.1 importer does not
				# enable its material flag; persist the explicit asset material.
				mesh.material_override = load("res://assets/characters/field_operator_20260904/vertex_palette.tres")
				var material := mesh.get_active_material(0) as BaseMaterial3D
				var arrays := mesh.mesh.surface_get_arrays(0)
				var colors := arrays[Mesh.ARRAY_COLOR] as PackedColorArray
				vertex_palette_imported = material != null and material.vertex_color_use_as_albedo and not colors.is_empty()
	var names: Array[String] = []
	for node in animations:
		var player := node as AnimationPlayer
		for animation_name in player.get_animation_list():
			names.append(animation_name)
		player.autoplay = "Animation"
	var bone_count := (skeletons[0] as Skeleton3D).get_bone_count() if skeletons.size() == 1 else 0
	var passed := bone_count == 41 and skin_count == 4 and meshes.size() == 4 and surface_count == 4 and vertex_palette_imported and not names.is_empty()
	if passed:
		var packed := PackedScene.new()
		var packed_error := packed.pack(scene)
		passed = packed_error == OK
		if passed:
			passed = ResourceSaver.save(packed, "res://assets/characters/field_operator_20260904/field_operator_aim_ready.scn") == OK
		if passed:
			var roundtrip := load("res://assets/characters/field_operator_20260904/field_operator_aim_ready.scn") as PackedScene
			var instance := roundtrip.instantiate()
			var roundtrip_mesh := instance.find_child("FieldOperator_OriginalSkinnedMesh", true, false) as MeshInstance3D
			passed = roundtrip_mesh != null and (roundtrip_mesh.material_override as BaseMaterial3D).vertex_color_use_as_albedo
			instance.free()
	print("FIELD_OPERATOR_GODOT_IMPORT ", JSON.stringify({
		"pass": passed, "native_bones": bone_count, "mesh_nodes": meshes.size(),
		"skinned_meshes": skin_count, "surfaces": surface_count, "animations": names,
		"vertex_palette_imported": vertex_palette_imported,
		"scope": "GLB structure and skin import only; not gameplay deformation proof"
	}))
	scene.queue_free()
	quit(0 if passed else 1)
