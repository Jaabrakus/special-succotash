extends "res://tools/agls_pullup_timing_review.gd"

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
	for label: String in ["ALSv2_Mantle_2m_Walking_01", "ALSv2_N_Vault_1m_RH"]:
		var path := "res://assets/external/agls_intake/imported/mantle_vault/" + label + ".scn"
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
		var result := {"source":path,"duration":raw.length,"root_delta_m":["phase","x","up","back"],"root_curve":curve,"samples":rows}
		if label == "ALSv2_Mantle_2m_Walking_01":
			var segment_start := 0.3
			var start_sample: Array = rows[6].raw.Hips
			var segment_curve: Array = []
			for row: Dictionary in rows:
				if float(row.phase) < segment_start: continue
				var value: Array = row.raw.Hips
				segment_curve.append([(float(row.phase)-segment_start)/(1.0-segment_start), float(value[0])-float(start_sample[0]), float(value[1])-float(start_sample[1]), float(value[2])-float(start_sample[2])])
			result["low_mantle_candidate"] = {"source_start_phase":segment_start,"source_end_phase":1.0,"source_duration_seconds":raw.length*(1.0-segment_start),"root_curve":segment_curve,"note":"Offline candidate for1.1m thickledge: source.30 startswrists1.12mabovebodyorigin; actualcollision/contact verification required."}
		clips.append(result)
		print("MANTLE_TIMING ", label, " duration=",raw.length," root_curve=",JSON.stringify(curve))
		source.free()
	var file := FileAccess.open("res://art_source/agls_traversal_review/mantle_timing.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"basis":"canonical scale62 rotationPI; rootposition zero; metres; offline only","clips":clips},"\t"))
	model.free()
	quit()
