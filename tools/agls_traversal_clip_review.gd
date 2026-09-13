extends SceneTree

const Adapter := preload("res://scripts/player/operator_native_rig_adapter.gd")
const OUT := "res://art_source/agls_traversal_review"
const CLIPS := ["CMC_Climb_Hanging_Idle_Loop", "CMC_Climb_To_Standing", "CMC_Climb_To_Standing_FreeHang", "CMC_Climb_Transition_Fall_To_Climb_01", "CMC_Climb_Transition_Fall_To_Climb_02", "CMC_Climb_Transition_Fall_To_Climb_03", "CMC_Climb_Transition_Fall_To_Climb_04", "CMC_Climb_Transition_Fall_To_Climb_05", "ALSv2_Mantle_2m_Walking_01", "ALSv2_Mantle_2m_Walking_02", "ALSv2_N_Vault_1m_RH", "ALSv2_N_Vault_1m_LH", "ALSv2_Vault_N_2m_LH"]

func _initialize() -> void:
	call_deferred("_run")

func _find(node: Node, type: String) -> Node:
	if node.is_class(type): return node
	for child in node.get_children():
		var result := _find(child, type)
		if result != null: return result
	return null

func _run() -> void:
	root.size = Vector2i(1440, 900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.1, 0.14)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.75
	world.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30, -30, 0)
	world.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.4
	world.add_child(camera)
	camera.current = true
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/operator_animation_map.json"))
	var reference := load(str(profile.clips.seal_stand_alert02)) as Animation
	var track := reference.find_track(NodePath(".:mixamorig_Hips"), Animation.TYPE_POSITION_3D)
	assert(track >= 0)
	var anchor := reference.position_track_interpolate(track, 0.0)
	var rows: Array = []
	for label: String in CLIPS:
		var family := "mantle_vault" if label.begins_with("ALSv2") else "climbing"
		var path := "res://assets/external/agls_intake/imported/%s/%s.scn" % [family, label]
		var source := load(path).instantiate() as Node3D
		var source_player := _find(source, "AnimationPlayer") as AnimationPlayer
		var source_skeleton := _find(source, "Skeleton3D") as Skeleton3D
		var source_name := ""
		for key in source_player.get_animation_list():
			if key != "RESET": source_name = key; break
		var models: Array[Node3D] = []
		var samples: Array = []
		for index in 3:
			var model := load("res://assets/characters/ps1_dual_source_rig/ps1_dual_source_rig.scn").instantiate() as Node3D
			world.add_child(model)
			model.scale = Vector3.ONE * 62.0
			model.rotation.y = PI
			model.position.x = (index - 1) * 1.5
			var skeleton := _find(model, "Skeleton3D") as Skeleton3D
			for previous in model.find_children("*", "AnimationPlayer", true, false): previous.free()
			var clip := Adapter.adapt_animation_rest_aware(source_player.get_animation(source_name), source_skeleton, skeleton, NodePath("."))
			var hips := clip.find_track(NodePath(".:mixamorig_Hips"), Animation.TYPE_POSITION_3D)
			if hips >= 0:
				for key in clip.track_get_key_count(hips): clip.track_set_key_value(hips, key, anchor)
			var player := AnimationPlayer.new()
			skeleton.add_child(player)
			player.root_node = NodePath("..")
			var library := AnimationLibrary.new()
			library.add_animation("review", clip)
			player.add_animation_library("", library)
			player.play("review")
			player.seek(clip.length * [0.0, 0.5, 0.99][index], true)
			player.pause()
			skeleton.force_update_all_bone_transforms()
			var bones := {}
			for name in ["Hips", "Head", "LeftArm", "RightArm", "LeftForeArm", "RightForeArm", "LeftHand", "RightHand", "LeftFoot", "RightFoot"]:
				var point := skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_" + name)).origin) - model.position
				bones[name] = [point.x, point.y, point.z]
			samples.append({"phase":[0.0, 0.5, 0.99][index], "bones":bones})
			models.append(model)
		await process_frame
		for view in ["front", "side"]:
			for index in models.size():
				models[index].rotation.y = PI if view == "front" else PI * 0.5
			camera.position = Vector3(0.0, 1.25, 6.0)
			camera.look_at(Vector3(0, 1.25, 0))
			await process_frame
			await RenderingServer.frame_post_draw
			assert(root.get_texture().get_image().save_png(OUT + "/godot_" + label + "_" + view + ".png") == OK)
		rows.append({"clip":label, "path":path, "duration":source_player.get_animation(source_name).length, "samples":samples})
		for model in models: model.free()
		source.free()
		print("AGLS_POSE_REVIEW ", label, " ", JSON.stringify(samples[0]))
	var file := FileAccess.open(OUT + "/godot_metrics.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"stage":"offline canonical model anchored hips; no IK; not integrated", "rows":rows}, "\t"))
	quit()
