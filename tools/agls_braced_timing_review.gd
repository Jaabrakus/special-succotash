extends "res://tools/agls_pullup_timing_review.gd"

func _pose(skeleton: Skeleton3D, clip: Animation, time: float) -> Dictionary:
	var result := super._pose(skeleton, clip, time)
	for name in ["LeftLeg", "RightLeg"]:
		var point := skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_" + name)).origin)
		result[name] = [point.x, point.y, point.z]
	return result

func _run() -> void:
	var model := load("res://assets/characters/ps1_dual_source_rig/ps1_dual_source_rig.scn").instantiate() as Node3D
	root.add_child(model)
	model.scale = Vector3.ONE * 62.0
	model.rotation.y = PI
	var skeleton := _find(model, "Skeleton3D") as Skeleton3D
	for player in model.find_children("*", "AnimationPlayer", true, false): player.free()
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/operator_animation_map.json"))
	var stand := load(str(profile.clips.seal_stand_alert02)) as Animation
	var anchor := stand.position_track_interpolate(stand.find_track(NodePath(".:mixamorig_Hips"), Animation.TYPE_POSITION_3D), 0.0)
	var clips: Array = []
	for label: String in ["CMC_Climb_To_Standing", "CMC_Climb_Hanging_Idle_Loop"]:
		var path := "res://assets/external/agls_intake/imported/climbing/" + label + ".scn"
		var source := load(path).instantiate() as Node3D
		var source_player := _find(source, "AnimationPlayer") as AnimationPlayer
		var source_skeleton := _find(source, "Skeleton3D") as Skeleton3D
		var name := ""
		for candidate in source_player.get_animation_list():
			if candidate != "RESET": name = candidate; break
		var raw := Adapter.adapt_animation_rest_aware(source_player.get_animation(name), source_skeleton, skeleton, NodePath("."))
		var anchored := raw.duplicate() as Animation
		var hips := anchored.find_track(NodePath(".:mixamorig_Hips"), Animation.TYPE_POSITION_3D)
		for key in anchored.track_get_key_count(hips): anchored.track_set_key_value(hips, key, anchor)
		var rows: Array = []
		for index in 21:
			var phase := float(index) / 20.0
			rows.append({"phase":phase,"seconds":phase*raw.length,"raw":_pose(skeleton,raw,phase*raw.length),"anchored":_pose(skeleton,anchored,phase*raw.length)})
		var first: Array = rows[0].raw.Hips
		var curve: Array = []
		for row: Dictionary in rows:
			var value: Array = row.raw.Hips
			curve.append([row.phase, float(value[0])-float(first[0]), float(value[1])-float(first[1]), float(value[2])-float(first[2])])
		clips.append({"source":path,"duration":raw.length,"root_delta_m":["phase","x","up","back"],"root_curve":curve,"samples":rows})
		print("BRACED_TIMING ", label, " duration=",raw.length," root_curve=",JSON.stringify(curve))
		source.free()
	var file := FileAccess.open("res://art_source/agls_traversal_review/braced_timing.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"basis":"canonical scale62 rotationPI; rootposition zero; metres; knees are LeftLeg/RightLeg; offline only","clips":clips},"\t"))
	model.free()
	quit()
