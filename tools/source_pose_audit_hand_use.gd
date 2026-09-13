extends SceneTree

## Original decoded source hierarchy only. No target retarget, IK or grip fit.
const Importer = preload("res://tools/import_seal_reference_animations.gd")
const Retarget = preload("res://scripts/labs/animation_retarget_service.gd")
const INPUT := "/private/tmp/socom-iso-motion-audit-20260912/motion/"
const SKELETON := "/Users/kiwimango/Downloads/SOCOM-II-animation-extractor/output/seal-skeleton.json"
const CLIPS := ["seal_p_stand", "seal_p_run", "seal_p_walk", "seal_pfp_stand", "seal_pfp_run", "seal_pfp_crouch", "seal_p_rstrafe_fast", "seal_p_lstrafe_fast"]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var skeleton_data: Dictionary = Importer.read_json(SKELETON)
	var skeleton: Skeleton3D = Importer.build_source_skeleton(skeleton_data)
	root.add_child(skeleton)
	var service := Retarget.new()
	var hierarchy: Array = []
	var source_names: Dictionary = {}
	for item: Dictionary in skeleton_data.nodes:
		hierarchy.append({"name": item.name, "parent": item.parent})
		source_names[item.name] = true
	var report := {"scope": "original source FK, no retarget or IK; source units not meters; omitted engine aim composition unproven", "skeleton_sha256": FileAccess.get_sha256(SKELETON), "source_hierarchy": hierarchy, "clips": []}
	for clip_name: String in CLIPS:
		var raw: Dictionary = Importer.read_json(INPUT + clip_name + ".json")
		var animation: Animation = Importer.build_source_animation(raw, skeleton)
		var channels: Dictionary = service._source_channels(animation, skeleton)
		var wrist_min := INF
		var wrist_max := 0.0
		var wrist_sum := 0.0
		var left_relative: Array[Vector3] = []
		var right_relative: Array[Vector3] = []
		var left_in_right_frame: Array[Vector3] = []
		var left_lengths: Array[float] = []
		var samples: Array = []
		var detached_tracks: Array = []
		var track_inventory: Array = []
		for track: Dictionary in raw.tracks:
			track_inventory.append({"name": track.name, "position_samples": track.positions_raw.size(), "rotation_samples": track.rotations_raw.size(), "recovered_parent": source_names.has(track.name)})
			if not source_names.has(track.name):
				detached_tracks.append({"name": track.name, "first_local_position_source_units": vector(Vector3(track.positions_raw[0][0], track.positions_raw[0][1], track.positions_raw[0][2]) / 256.0), "first_rotation_xyzw_raw": track.rotations_raw[0]})
		for frame in int(raw.samples):
			var time := animation.length * float(frame) / float(raw.frames)
			var globals: Dictionary = service._sample_source_global_transforms(animation, skeleton, channels, time)
			var chest: Transform3D = globals[skeleton.find_bone("mixamorig_Spine2")]
			var lh: Vector3 = (globals[skeleton.find_bone("mixamorig_LeftHand")] as Transform3D).origin
			var rh: Vector3 = (globals[skeleton.find_bone("mixamorig_RightHand")] as Transform3D).origin
			var le: Vector3 = (globals[skeleton.find_bone("mixamorig_LeftForeArm")] as Transform3D).origin
			var ls: Vector3 = (globals[skeleton.find_bone("mixamorig_LeftArm")] as Transform3D).origin
			var re: Vector3 = (globals[skeleton.find_bone("mixamorig_RightForeArm")] as Transform3D).origin
			var rs: Vector3 = (globals[skeleton.find_bone("mixamorig_RightArm")] as Transform3D).origin
			var gap := lh.distance_to(rh)
			wrist_min = minf(wrist_min, gap)
			wrist_max = maxf(wrist_max, gap)
			wrist_sum += gap
			left_lengths.append(ls.distance_to(le) + le.distance_to(lh))
			left_relative.append(chest.affine_inverse() * lh)
			right_relative.append(chest.affine_inverse() * rh)
			left_in_right_frame.append((globals[skeleton.find_bone("mixamorig_RightHand")] as Transform3D).affine_inverse() * lh)
			if frame in [0, int(raw.frames) / 2, int(raw.frames)]:
				samples.append({"frame": frame, "left_shoulder": vector(ls), "left_elbow": vector(le), "left_wrist": vector(lh), "right_shoulder": vector(rs), "right_elbow": vector(re), "right_wrist": vector(rh), "chest": vector(chest.origin)})
		var arm_length: float = left_lengths.reduce(func(a: float, b: float): return a + b, 0.0) / left_lengths.size()
		report.clips.append({"name": clip_name, "duration": animation.length, "frames": raw.frames, "source_sha256": FileAccess.get_sha256(INPUT + clip_name + ".json"), "sparse_missing_hips": not channels.has(skeleton.find_bone("mixamorig_Hips")), "aimnodes_animated": channels.has(skeleton.find_bone("aimnodes")), "track_inventory": track_inventory, "detached_tracks_no_parent_contract": detached_tracks, "wrist_gap_min_source_units": wrist_min, "wrist_gap_max_source_units": wrist_max, "wrist_gap_mean_source_units": wrist_sum / raw.samples, "left_arm_length_source_units": arm_length, "wrist_gap_arm_fraction_min": wrist_min / arm_length, "wrist_gap_arm_fraction_max": wrist_max / arm_length, "left_wrist_chest_relative_travel_source_units": diameter(left_relative), "right_wrist_chest_relative_travel_source_units": diameter(right_relative), "left_wrist_in_right_wrist_frame_travel_source_units": diameter(left_in_right_frame), "early_middle_late": samples})
		assert(is_finite(wrist_min) and is_finite(wrist_max) and arm_length > 0.0, "Finite original source FK: " + clip_name)
		if clip_name in ["seal_p_run", "seal_pfp_run"]:
			assert(wrist_min / arm_length > 0.6, "Source running left hand remains free: " + clip_name)
			assert(diameter(left_relative) > diameter(right_relative) * 3.0, "Source running offhand swings independently: " + clip_name)
		if clip_name in ["seal_pfp_stand", "seal_pfp_crouch"]:
			assert(wrist_max / arm_length < 0.2, "Source stationary firing brings hands together: " + clip_name)
		if clip_name == "seal_p_rstrafe_fast":
			assert(wrist_max / arm_length < 0.2, "Source right strafe keeps wrists close")
			assert(diameter(left_relative) < 0.3 and diameter(right_relative) < 0.3, "Right strafe is not a free-arm forward-run swing")
		if clip_name == "seal_p_lstrafe_fast":
			assert(wrist_min / arm_length > 1.9, "Source left strafe keeps hands separated")
			assert(diameter(left_relative) > diameter(right_relative) * 2.0, "Source left strafe moves offhand independently")
	print("SOURCE_HAND_USE ", JSON.stringify(report))
	print("SOURCE_HAND_USE PASS: ", CLIPS.size(), " raw clips, no target skeleton or IK")
	skeleton.free()
	quit()

func vector(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func diameter(points: Array[Vector3]) -> float:
	var result := 0.0
	for first in points:
		for second in points:
			result = maxf(result, first.distance_to(second))
	return result
