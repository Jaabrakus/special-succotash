extends SceneTree

const IMPORTER := preload("res://tools/import_seal_reference_animations.gd")
const COMPOSER := preload("res://tools/extend_seal_locomotion_candidate.gd")
const OUTPUT := "res://assets/animations/seal_firing_reference/"
const BASES := {
	"seal_pfp_stand": "seal_p_stand", "seal_pfp_crouch": "seal_crouch",
	"seal_pfp_prone": "seal_prone", "seal_pfp_run": "seal_run",
	"seal_pfp_walk": "seal_walk", "seal_pfp_crouchwalk": "seal_crouchwalk",
	"seal_pfp_crouchwalk_bw": "seal_crouchwalk_bw",
}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1 and not DirAccess.dir_exists_absolute(OUTPUT), "Supply decoded output directory; do not overwrite an existing firing import")
	var input: String = args[0]
	var data: Dictionary = IMPORTER.read_json(input.path_join("seal-skeleton.json"))
	var catalog: Array = IMPORTER.read_json(input.path_join("animation-catalog.json"))
	var source_skeleton := IMPORTER.build_source_skeleton(data)
	root.add_child(source_skeleton)
	var target := (load(IMPORTER.TARGET) as PackedScene).instantiate()
	root.add_child(target)
	var service = IMPORTER.RETARGET.new()
	var target_skeleton: Skeleton3D = service._find_skeleton(target)
	var mapping := {}
	for alias: String in IMPORTER.ALIASES.values():
		mapping[alias] = alias
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var entries := {}
	for item: Dictionary in catalog:
		var name: String = item.name
		if not (name.begins_with("seal_fp_") or name.begins_with("seal_pfp_")):
			continue
		var input_path := input.path_join("motion/" + name + ".json")
		var decoded: Dictionary = IMPORTER.read_json(input_path)
		var source := IMPORTER.build_source_animation(decoded, source_skeleton)
		var baked: Animation = service.bake_rest_aware_animation(source, source_skeleton, target_skeleton, NodePath("."), mapping, float(decoded.frames) / source.length)
		var present := {}
		for channel: Dictionary in decoded.tracks:
			present[str(IMPORTER.ALIASES.get(channel.name, channel.name))] = true
		for track in range(baked.get_track_count() - 1, -1, -1):
			var bone := str(baked.track_get_path(track)).get_slice(":", 1)
			if not present.has(bone):
				baked.remove_track(track)
			elif baked.track_get_type(track) == Animation.TYPE_POSITION_3D:
				for key in baked.track_get_key_count(track):
					var value: Vector3 = baked.track_get_key_value(track, key)
					value.x = 0; value.z = 0
					baked.track_set_key_value(track, key, value)
		var settings := IMPORTER.settings_dictionary(item.get("settings", []))
		baked.resource_name = name
		baked.loop_mode = Animation.LOOP_LINEAR if bool(settings.get("looped", false)) else Animation.LOOP_NONE
		baked.set_meta("seal_reference", true)
		baked.set_meta("seal_firing_pose", true)
		baked.set_meta("source_name", name)
		baked.set_meta("source_sha256", FileAccess.get_sha256(input_path))
		baked.set_meta("source_settings", settings)
		baked.set_meta("source_coverage", "full" if present.has("mixamorig_Hips") else "upper")
		var path := OUTPUT + name + ".tres"
		assert(ResourceSaver.save(baked, path) == OK)
		entries[name] = {"path": path, "sha256": FileAccess.get_sha256(input_path), "coverage": baked.get_meta("source_coverage"), "duration": baked.length}
		if baked.get_meta("source_coverage") == "upper" and BASES.has(name):
			var base := load("res://assets/animations/seal_reference/" + BASES[name] + ".tres") as Animation
			var full := COMPOSER.compose(baked, base)
			var full_path := OUTPUT + name + "_composed.tres"
			assert(ResourceSaver.save(full, full_path) == OK)
			entries[name]["composed_path"] = full_path
			entries[name]["base"] = BASES[name]
	var file := FileAccess.open(OUTPUT + "manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"entries": entries, "source_animset_sha256": FileAccess.get_sha256(input.path_join("readers/animset.rdr.json")), "meaning": "Source animset names these firing poses, not first-person. Weapon/helper parent mapping is not recovered."}, "\t") + "\n")
	file.close()
	print("SEAL_FIRING_IMPORT PASS count=", entries.size())
	target.free()
	source_skeleton.free()
	quit()
