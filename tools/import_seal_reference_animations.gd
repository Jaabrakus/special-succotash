extends SceneTree

const RETARGET = preload("res://scripts/labs/animation_retarget_service.gd")
const OUTPUT := "res://assets/animations/seal_reference"
const TARGET := "res://assets/characters/ps1_dual_source_rig/ps1_dual_source_rig.scn"
const ALIASES := {
	"hips": "mixamorig_Hips", "spinelo": "mixamorig_Spine",
	"spinehi": "mixamorig_Spine2", "neck": "mixamorig_Neck", "head": "mixamorig_Head",
	"rscap": "mixamorig_RightShoulder", "rbicep": "mixamorig_RightArm",
	"rforearm": "mixamorig_RightForeArm", "rhand": "mixamorig_RightHand",
	"lscap": "mixamorig_LeftShoulder", "lbicep": "mixamorig_LeftArm",
	"lforearm": "mixamorig_LeftForeArm", "lhand": "mixamorig_LeftHand",
	"rthigh": "mixamorig_RightUpLeg", "rcalf": "mixamorig_RightLeg",
	"rfoot": "mixamorig_RightFoot", "rtoe": "mixamorig_RightToeBase",
	"lthigh": "mixamorig_LeftUpLeg", "lcalf": "mixamorig_LeftLeg",
	"lfoot": "mixamorig_LeftFoot", "ltoe": "mixamorig_LeftToeBase",
}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DirAccess.dir_exists_absolute(OUTPUT):
		push_error("Supply reviewed viewer data directory after --; output must not already exist.")
		quit(1)
		return
	var source_dir := args[0]
	var catalog: Array = read_json(source_dir.path_join("catalog.json"))
	var classifications: Dictionary = read_json(source_dir.path_join("classification.json"))["clips"]
	var skeleton_data: Dictionary = read_json(source_dir.path_join("skeleton.json"))
	var source_skeleton := build_source_skeleton(skeleton_data)
	root.add_child(source_skeleton)
	var target_root := (load(TARGET) as PackedScene).instantiate()
	root.add_child(target_root)
	var service = RETARGET.new()
	var target_skeleton: Skeleton3D = service._find_skeleton(target_root)
	var mapping := {}
	for alias: String in ALIASES.values():
		assert(target_skeleton.find_bone(alias) >= 0, "Missing target bone: " + alias)
		mapping[alias] = alias
	var entries: Array = []
	# Validate input coverage before producing files.
	for item: Dictionary in catalog:
		if selected(item.name):
			assert(classifications.has(item.name))
			assert(FileAccess.file_exists(source_dir.path_join("motion/" + item.name + ".json")))
	assert(catalog.filter(func(item): return selected(item.name)).size() == 261)
	assert(DirAccess.make_dir_recursive_absolute(OUTPUT) == OK)
	for item: Dictionary in catalog:
		var clip_name: String = item.name
		if not selected(clip_name):
			continue
		var source_path := source_dir.path_join("motion/" + clip_name + ".json")
		var decoded: Dictionary = read_json(source_path)
		var source := build_source_animation(decoded, source_skeleton)
		var settings := settings_dictionary(item.get("settings", []))
		var classification: Dictionary = classifications[clip_name]
		var loops := bool(settings.get("looped", false)) and not bool(classification.isStatic)
		# Sample without wrap at the saved end key. Apply source loop policy after baking.
		var baked: Animation = service.bake_rest_aware_animation(
			source, source_skeleton, target_skeleton, NodePath("."), mapping,
			float(decoded.frames) / source.length
		)
		var present := {}
		for channel: Dictionary in decoded.tracks:
			present[str(ALIASES.get(channel.name, channel.name))] = true
		for track in range(baked.get_track_count() - 1, -1, -1):
			var bone := str(baked.track_get_path(track)).get_slice(":", 1)
			if not present.has(bone):
				baked.remove_track(track)
			elif baked.track_get_type(track) == Animation.TYPE_POSITION_3D:
				# Root motion stays presentation-only; preserve vertical stance displacement.
				for key in baked.track_get_key_count(track):
					var value: Vector3 = baked.track_get_key_value(track, key)
					value.x = 0.0
					value.z = 0.0
					baked.track_set_key_value(track, key, value)
		baked.resource_name = clip_name
		baked.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE
		baked.set_meta("seal_reference", true)
		baked.set_meta("source_name", clip_name)
		baked.set_meta("source_sha256", FileAccess.get_sha256(source_path))
		baked.set_meta("source_settings", settings)
		baked.set_meta("source_static", bool(classification.isStatic))
		baked.set_meta("source_coverage", str(classification.coverage))
		baked.set_meta("target_rig_sha256", FileAccess.get_sha256(TARGET))
		var path := OUTPUT.path_join(clip_name + ".tres")
		assert(ResourceSaver.save(baked, path) == OK)
		var family := "Death" if clip_name.begins_with("death_") else (
			"Pistol" if clip_name.begins_with("seal_p_") else "Rifle Common"
		)
		var label := "STATIC" if bool(classification.isStatic) else "MOTION"
		if str(classification.coverage) != "full":
			label += " PARTIAL"
		entries.append({
			"name": clip_name, "path": path,
			"display": "SEAL %s [%s] %s" % [family, label, clip_name],
			"family": family, "classification": classification, "duration": source.length,
			"source_frames": decoded.frames, "source_samples": decoded.samples,
			"source_sha256": FileAccess.get_sha256(source_path), "settings": settings,
			"loop": loops, "track_count": baked.get_track_count(),
		})
	var manifest := {
		"version": 1, "status": "reference candidates; not active gameplay defaults",
		"target_rig": TARGET, "target_rig_sha256": FileAccess.get_sha256(TARGET),
		"source_skeleton_sha256": FileAccess.get_sha256(source_dir.path_join("skeleton.json")),
		"clips": entries, "count": entries.size(),
	}
	var file := FileAccess.open(OUTPUT.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	file.close()
	print("SEAL_IMPORT PASS: ", entries.size(), " separate authored clips; default mappings untouched")
	target_root.free()
	source_skeleton.free()
	quit()

static func selected(clip_name: String) -> bool:
	return clip_name.begins_with("death_") or (
		clip_name.begins_with("seal_") and not clip_name.begins_with("seal_fp_")
		and not clip_name.begins_with("seal_pfp_")
	)

static func read_json(path: String) -> Variant:
	assert(FileAccess.file_exists(path), "Missing source " + path)
	return JSON.parse_string(FileAccess.get_file_as_string(path))

static func settings_dictionary(raw: Variant) -> Dictionary:
	var result := {}
	if not raw is Array:
		return result
	for index in range(0, raw.size(), 2):
		if index + 1 < raw.size():
			var value: Variant = raw[index + 1]
			result[str(raw[index])] = value[0] if value is Array and value.size() == 1 else value
	return result

static func build_source_skeleton(data: Dictionary) -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = "RecoveredSEALSkeleton"
	for item: Dictionary in data.nodes:
		var bone_name := str(ALIASES.get(item.name, item.name))
		skeleton.add_bone(bone_name)
		var index := skeleton.find_bone(bone_name)
		if item.parent != null:
			var parent := skeleton.find_bone(str(ALIASES.get(item.parent, item.parent)))
			assert(parent >= 0, "Source hierarchy must be parent-first")
			skeleton.set_bone_parent(index, parent)
		var m: Array = item.matrix_column_major
		var transform := Transform3D(Basis(Vector3(m[0], m[1], m[2]),
			Vector3(m[4], m[5], m[6]), Vector3(m[8], m[9], m[10])),
			Vector3(m[12], m[13], m[14]))
		skeleton.set_bone_rest(index, transform)
	return skeleton

static func build_source_animation(data: Dictionary, skeleton: Skeleton3D) -> Animation:
	var animation := Animation.new()
	animation.length = float(data.duration)
	assert(animation.length > 0.0 and int(data.frames) > 0)
	for channel: Dictionary in data.tracks:
		var bone_name := str(ALIASES.get(channel.name, channel.name))
		if skeleton.find_bone(bone_name) < 0:
			continue # Detached weapon/helper tracks have no recovered parent contract.
		for kind in ["positions_raw", "rotations_raw"]:
			var samples: Array = channel[kind]
			assert(samples.size() == 1 or samples.size() == int(data.samples))
			var track := animation.add_track(Animation.TYPE_POSITION_3D
				if kind == "positions_raw" else Animation.TYPE_ROTATION_3D)
			animation.track_set_path(track, NodePath(".:" + bone_name))
			animation.track_set_interpolation_loop_wrap(track, false)
			for index in samples.size():
				var time := float(index) * animation.length / float(data.frames)
				var value: Array = samples[index]
				if kind == "positions_raw":
					animation.position_track_insert_key(track, time,
						Vector3(value[0], value[1], value[2]) / 256.0)
				else:
					var rotation := Quaternion(value[0], value[1], value[2], value[3])
					assert(rotation.length_squared() > 0.0)
					animation.rotation_track_insert_key(track, time, rotation.normalized())
	return animation
