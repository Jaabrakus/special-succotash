extends SceneTree

const OUT := "res://art_source/traversal_character_workbench"
const Adapter := preload("res://scripts/player/operator_native_rig_adapter.gd")

func _initialize() -> void:
	call_deferred("_run")

func _find(node: Node, type: String) -> Node:
	if node.is_class(type): return node
	for child in node.get_children():
		var result := _find(child, type)
		if result != null: return result
	return null

func _source_paths(value: Variant, route: String = "profile") -> Array:
	var result: Array = []
	if value is Dictionary:
		for key in value: result.append_array(_source_paths(value[key], route + "_" + str(key)))
	elif value is Array:
		for index in value.size(): result.append_array(_source_paths(value[index], route + "_" + str(index)))
	elif value is String and value.begins_with("res://assets/animations/seal_") and value.ends_with(".tres"):
		result.append({"slot": route, "source": value})
	return result

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var model := load("res://assets/characters/ps1_dual_source_rig/ps1_dual_source_rig.scn").instantiate() as Node3D
	# Export a neutral parent so the canonical model transform is not discarded
	# when GLTFDocument treats its supplied node as the export root.
	var review_root := Node3D.new()
	review_root.name = "CanonicalCharacterReview"
	root.add_child(review_root)
	review_root.add_child(model)
	model.scale = Vector3.ONE * 62.0
	model.rotation.y = PI
	var skeleton := _find(model, "Skeleton3D") as Skeleton3D
	var removed_unskinned: Array[String] = []
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.skin == null:
			removed_unskinned.append(str(mesh.name))
			mesh.free()
	for previous in model.find_children("*", "AnimationPlayer", true, false): previous.free()
	var animation_player := AnimationPlayer.new()
	skeleton.add_child(animation_player)
	animation_player.root_node = NodePath("..")
	var library := AnimationLibrary.new()
	animation_player.add_animation_library("", library)
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/operator_animation_map.json"))
	var rows: Array = []
	var exported_paths: Dictionary = {}
	for slot in profile.clips:
		var path := str(profile.clips[slot])
		if not path.begins_with("res://assets/animations/seal_"): continue
		var clip := load(path).duplicate() as Animation
		if clip == null: continue
		library.add_animation(str(slot), clip)
		rows.append({"slot":slot,"source":path,"duration":clip.length,"status":"character_retargeted_review_not_new_runtime_replacement"})
		exported_paths[path] = true
	for entry in _source_paths(profile):
		if exported_paths.has(entry.source): continue
		var clip := load(str(entry.source)).duplicate() as Animation
		assert(clip != null, str(entry.source))
		library.add_animation(str(entry.slot), clip)
		rows.append({"slot":entry.slot,"source":entry.source,"duration":clip.length,"status":"character_retargeted_review_not_new_runtime_replacement"})
		exported_paths[entry.source] = true
	var routes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/traversal_animation_map.json"))
	var inventory: Array = []
	for family: String in ["climbing", "mantle_vault", "ladder", "narrow_ledge", "rope", "zipline", "locomotion_air"]:
		for label in routes.families[family]:
			var path := str(routes.families[family][label])
			var source := load(path).instantiate() as Node3D
			var source_player := _find(source, "AnimationPlayer") as AnimationPlayer
			var source_skeleton := _find(source, "Skeleton3D") as Skeleton3D
			var name := ""
			for key in source_player.get_animation_list():
				if key != "RESET": name = key; break
			var clip := Adapter.adapt_animation_rest_aware(source_player.get_animation(name), source_skeleton, skeleton, NodePath("."))
			assert(clip.get_track_count() > 20, path)
			for track in clip.get_track_count():
				assert(skeleton.find_bone(str(clip.track_get_path(track)).get_slice(":", 1)) >= 0, path)
			var key := "AGLS_" + path.get_file().get_basename()
			library.add_animation(key, clip)
			inventory.append({"family":family,"clip":key,"path":path,"duration":clip.length,"tracks":clip.get_track_count(),"status":"retargeted_for_character_review_not_runtime_state"})
			source.free()
		print("WORKBENCH_FAMILY ", family, " count=", routes.families[family].size())
	animation_player.play("seal_stand_alert02")
	animation_player.advance(0.0)
	var reference_points: Dictionary = {}
	for bone: String in ["mixamorig_Head", "mixamorig_Hips", "mixamorig_LeftHand", "mixamorig_RightHand"]:
		var point := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone)).origin
		reference_points[bone] = [point.x, point.y, point.z]
	animation_player.stop()
	skeleton.reset_bone_poses()
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_scene(review_root, state) == OK)
	assert(document.write_to_filesystem(state, OUT + "/character_actions.glb") == OK)
	var file := FileAccess.open(OUT + "/inventory.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"socom_runtime_slots":rows,"agls_clips":inventory,"skeleton_bones":skeleton.get_bone_count(),"runtime_replacements_promoted":false,"removed_unskinned_meshes":removed_unskinned,"canonical_model_scale":62.0,"canonical_model_yaw_radians":PI,"godot_standing_reference_points":reference_points}, "\t"))
	print("CHARACTER_WORKBENCH_EXPORT PASS SOCOM=", rows.size(), " AGLS=", inventory.size())
	review_root.queue_free()
	await process_frame
	quit()
