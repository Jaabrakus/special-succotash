extends SceneTree

const REPOSITORY = preload("res://scripts/labs/animation_workshop_repository.gd")
const RETARGET = preload("res://scripts/labs/animation_retarget_service.gd")
const ROOT_SANITIZER = preload("res://scripts/player/operator_animation_root_sanitizer.gd")
const IMPORTER = preload("res://tools/import_seal_reference_animations.gd")
const RUNTIME = preload("res://scripts/player/operator_asset_runtime.gd")
const PROFILE = preload("res://scripts/player/operator_animation_profile.gd")
const STUDIO_MODEL = preload("res://scripts/labs/animation_studio/animation_studio_model.gd")
const MANIFEST := "res://assets/animations/seal_reference/manifest.json"
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("SEAL_REFERENCE FAIL: " + message)

func _run() -> void:
	var manifest: Dictionary = IMPORTER.read_json(MANIFEST)
	var model := (load(manifest.target_rig) as PackedScene).instantiate()
	root.add_child(model)
	var service = RETARGET.new()
	var skeleton: Skeleton3D = service._find_skeleton(model)
	var player := AnimationPlayer.new()
	skeleton.add_child(player)
	player.root_node = NodePath("..")
	var library := AnimationLibrary.new()
	player.add_animation_library("reference", library)
	var repo = REPOSITORY.new()
	var scanned: Dictionary = repo.scan_seal_reference()
	check(scanned.size() == 261, "all 261 entries discovered")
	check(FileAccess.get_sha256(manifest.target_rig) == manifest.target_rig_sha256,
		"target rig fingerprint unchanged")
	var entries: Array = repo.build_entries([], {}, scanned)
	check(entries.size() == 261, "normal authored catalog can display all imports")
	var catalog_by_path := {}
	for catalog_item: Dictionary in entries:
		catalog_by_path[str(catalog_item.path)] = catalog_item
	var counts := {"Pistol": 0, "Rifle Common": 0, "Death": 0}
	var poses := 0
	for entry: Dictionary in manifest.clips:
		counts[entry.family] += 1
		var clip := load(str(entry.path)) as Animation
		check(clip != null, "load " + str(entry.name))
		if clip == null:
			continue
		check(absf(clip.length - float(entry.duration)) < 0.00001, entry.name + " duration")
		check((clip.loop_mode == Animation.LOOP_LINEAR) == bool(entry.loop), entry.name + " loop")
		check(clip.get_meta("source_sha256", "") == entry.source_sha256, entry.name + " provenance")
		check(clip.get_track_count() > 0, entry.name + " has target tracks")
		var paths := {}
		for track in clip.get_track_count():
			var bone := str(clip.track_get_path(track)).get_slice(":", 1)
			check(skeleton.find_bone(bone) >= 0, entry.name + " resolves " + bone)
			var typed_path := str(clip.track_get_path(track)) + str(clip.track_get_type(track))
			check(not paths.has(typed_path), entry.name + " unique typed track")
			paths[typed_path] = true
			for key in clip.track_get_key_count(track):
				var value: Variant = clip.track_get_key_value(track, key)
				if value is Quaternion:
					check(value.is_finite() and absf(value.length() - 1.0) < 0.001,
						entry.name + " finite normalized rotation")
				elif value is Vector3:
					check(value.is_finite() and absf(value.x) + absf(value.z) < 0.000001,
						entry.name + " presentation-only translation")
		if entry.name == "seal_p_run":
			for track in clip.get_track_count():
				check(not "Hips" in str(clip.track_get_path(track))
					and not "Leg" in str(clip.track_get_path(track)), "pistol overlay must not invent legs")
		var catalog_entry: Dictionary = catalog_by_path[entry.path]
		check(service.load_authored(catalog_entry, library, player, skeleton,
			false, {}, not bool(entry.loop), ROOT_SANITIZER), entry.name + " loads through Studio")
		var loaded := library.get_animation(catalog_entry.key)
		check(loaded.loop_mode == clip.loop_mode, entry.name + " ignores generic loop heuristic")
		for time in [0.0, clip.length * 0.5, clip.length]:
			skeleton.reset_bone_poses()
			player.play("reference/" + str(catalog_entry.key))
			player.seek(time, true)
			skeleton.force_update_all_bone_transforms()
			for track in loaded.get_track_count():
				var bone := str(loaded.track_get_path(track)).get_slice(":", 1)
				var index := skeleton.find_bone(bone)
				if loaded.track_get_type(track) == Animation.TYPE_ROTATION_3D:
					var expected := loaded.rotation_track_interpolate(track, time)
					check(absf(expected.dot(skeleton.get_bone_pose_rotation(index))) > 0.999,
						entry.name + " actual AnimationPlayer bone rotation " + bone)
				else:
					check(skeleton.get_bone_pose_position(index).distance_to(
						loaded.position_track_interpolate(track, time)) < 0.00001,
						entry.name + " actual AnimationPlayer bone translation " + bone)
			poses += 1
		player.stop()
	check(counts == {"Pistol": 79, "Rifle Common": 160, "Death": 22}, "family counts")
	# Studio's default PS1 skin is still the original native mesh. Exercise its
	# actual name-normalization helper and confirm the mapped rest frames agree.
	var preview_model := (load("res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx") as PackedScene).instantiate()
	root.add_child(preview_model)
	var preview_skeleton: Skeleton3D = service._find_skeleton(preview_model)
	var studio_helpers = STUDIO_MODEL.new()
	studio_helpers._normalize_skeleton_bones(preview_skeleton)
	studio_helpers.free()
	for bone: String in IMPORTER.ALIASES.values():
		var preview_index := preview_skeleton.find_bone(bone)
		check(preview_index >= 0, "Studio skin contains " + bone)
		if preview_index < 0:
			continue
		var a := preview_skeleton.get_bone_global_rest(preview_index)
		var b := skeleton.get_bone_global_rest(skeleton.find_bone(bone))
		check(a.origin.distance_to(b.origin) * 62.0 < 0.001,
			"Studio/canonical rest origin within 1mm: " + bone)
		check(absf(a.basis.orthonormalized().get_rotation_quaternion().dot(
			b.basis.orthonormalized().get_rotation_quaternion())) > 0.99999,
			"Studio/canonical rest orientation agrees: " + bone)
	preview_model.free()
	# Exercise the real canonical authored-resource loader with an isolated,
	# in-memory profile. No saved gameplay mapping or packaged cache is written.
	var test_profile = PROFILE.new()
	test_profile.clip_paths.clear()
	test_profile.mirrored_clips.clear()
	test_profile.leg_mirrored_clips.clear()
	test_profile.clip_aliases.clear()
	test_profile.pose_yaw_offsets_degrees.clear()
	for entry: Dictionary in manifest.clips:
		test_profile.clip_paths[StringName(entry.name)] = entry.path
	var runtime = RUNTIME.new()
	runtime.profile = test_profile
	runtime.skeleton = skeleton
	runtime.animation_player = player
	runtime._build_animation_library()
	check(runtime.available_clips.size() == 261, "canonical runtime accepts all authored resources")
	for entry: Dictionary in manifest.clips:
		var runtime_clip: Animation = runtime.animation_library.get_animation(entry.name)
		check(runtime_clip != null and is_equal_approx(runtime_clip.length, float(entry.duration)),
			entry.name + " runtime source duration")
		check(str(runtime.source_animation_names.get(StringName(entry.name), "")).begins_with("authored:"),
			entry.name + " runtime consumed authored path")
	# Wrong skeleton must be rejected, not silently name-guessed.
	var wrong := Skeleton3D.new()
	wrong.add_bone("WrongHip")
	check(not service.load_authored({"key": "wrong", "path": manifest.clips[0].path},
		library, null, wrong, false, {}, true, ROOT_SANITIZER), "incompatible rig rejected")
	wrong.free()
	model.free()
	print("SEAL_REFERENCE_RESULT ", "PASS" if failures == 0 else "FAIL", " clips=261 poses=", poses,
		" failures=", failures)
	quit(0 if failures == 0 else 1)
