extends SceneTree

const Adapter := preload("res://scripts/player/operator_native_rig_adapter.gd")
const SOURCE := "res://assets/external/agls_intake/imported/climbing/CMC_Climb_To_Standing_FreeHang.scn"

func _initialize() -> void:
	call_deferred("_run")

func _find(node: Node, type: String) -> Node:
	if node.is_class(type): return node
	for child in node.get_children():
		var found := _find(child, type)
		if found != null: return found
	return null

func _pose(skeleton: Skeleton3D, clip: Animation, time: float) -> Dictionary:
	skeleton.reset_bone_poses()
	for track in clip.get_track_count():
		var bone := skeleton.find_bone(str(clip.track_get_path(track)).get_slice(":", 1))
		if bone < 0: continue
		match clip.track_get_type(track):
			Animation.TYPE_ROTATION_3D: skeleton.set_bone_pose_rotation(bone, clip.rotation_track_interpolate(track, time))
			Animation.TYPE_POSITION_3D: skeleton.set_bone_pose_position(bone, clip.position_track_interpolate(track, time))
			Animation.TYPE_SCALE_3D: skeleton.set_bone_pose_scale(bone, clip.scale_track_interpolate(track, time))
	skeleton.force_update_all_bone_transforms()
	var result := {}
	for name in ["Hips", "Head", "LeftArm", "RightArm", "LeftHand", "RightHand", "LeftFoot", "RightFoot", "LeftUpLeg", "RightUpLeg"]:
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
	var source := load(SOURCE).instantiate() as Node3D
	var source_player := _find(source, "AnimationPlayer") as AnimationPlayer
	var source_skeleton := _find(source, "Skeleton3D") as Skeleton3D
	var name := ""
	for candidate in source_player.get_animation_list():
		if candidate != "RESET": name = candidate; break
	var raw := Adapter.adapt_animation_rest_aware(source_player.get_animation(name), source_skeleton, skeleton, NodePath("."))
	var anchored := raw.duplicate() as Animation
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/operator_animation_map.json"))
	var stand := load(str(profile.clips.seal_stand_alert02)) as Animation
	var anchor := stand.position_track_interpolate(stand.find_track(NodePath(".:mixamorig_Hips"), Animation.TYPE_POSITION_3D), 0.0)
	var hips := anchored.find_track(NodePath(".:mixamorig_Hips"), Animation.TYPE_POSITION_3D)
	for key in anchored.track_get_key_count(hips): anchored.track_set_key_value(hips, key, anchor)
	var rows: Array = []
	for index in 21:
		var phase := float(index) / 20.0
		var row := {"phase":phase,"seconds":phase*raw.length,"raw":_pose(skeleton,raw,phase*raw.length),"anchored":_pose(skeleton,anchored,phase*raw.length)}
		rows.append(row)
		print("PULLUP_TIMING ", JSON.stringify(row))
	var file := FileAccess.open("res://art_source/agls_traversal_review/pullup_timing.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"source":SOURCE,"duration":raw.length,"basis":"canonical scale62 rotationPI; rootposition zero; metres","samples":rows},"\t"))
	source.free()
	model.free()
	quit()
