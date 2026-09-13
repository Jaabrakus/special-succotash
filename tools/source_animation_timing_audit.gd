extends SceneTree

## Offline observer. No source/runtime/profile writes; optional NEW report only.
const Profile = preload("res://scripts/player/operator_animation_profile.gd")
const AssetRuntime = preload("res://scripts/player/operator_asset_runtime.gd")
const WeaponContract = preload("res://scripts/weapons/weapon_rig_contract.gd")
const RAW := "/private/tmp/socom-iso-motion-audit-20260912/motion"
const CATALOG := "/Users/kiwimango/Downloads/SOCOM-II-animation-extractor/output/animation-catalog.json"
const MAP := "res://config/operator_animation_map.json"
const SOURCE_DIRS := ["res://assets/animations/seal_reference", "res://assets/animations/seal_firing_reference", "res://assets/animations/seal_gameplay"]
var failures: Array[String] = []
var input_hashes: Dictionary = {}
var resources: Dictionary = {}
var raw_sources: Dictionary = {}
var asset_reader = AssetRuntime.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var output := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		else:
			_check(false, "Unknown argument: " + argument)
	if not output.is_empty():
		_check(output.begins_with("res://art_source/") and output == output.simplify_path() and output.ends_with(".json"), "Output must be a canonical project art_source JSON path")
		_check(not FileAccess.file_exists(output), "Refusing to overwrite report: " + output)
		_check(DirAccess.dir_exists_absolute(output.get_base_dir()), "Output parent must already exist")
	if not failures.is_empty():
		_finish({})
		return
	var catalog: Array = _json(CATALOG)
	var settings: Dictionary = {}
	for row: Dictionary in catalog:
		settings[String(row.name)] = row
	var files := DirAccess.get_files_at(RAW)
	files.sort()
	var max_hz_error := 0.0
	for file: String in files:
		if not file.begins_with("seal_") or not file.ends_with(".json"):
			continue
		var name := file.get_basename()
		var raw: Dictionary = _json(RAW.path_join(file))
		var binary_path := RAW.path_join(name + ".bin")
		_track_input(binary_path)
		var binary := FileAccess.open(binary_path, FileAccess.READ)
		if binary == null:
			_check(false, "Missing binary " + name)
			continue
		var version := binary.get_32()
		var duration := binary.get_float()
		var frames := binary.get_32()
		var bones := binary.get_32()
		binary.close()
		_check(version == 5 and version == int(raw.version), "Version " + name)
		_check(frames == int(raw.frames) and bones == int(raw.bone_count), "Binary counts " + name)
		_check(absf(duration - float(raw.duration)) < 0.0000001 and duration > 0.0, "Binary duration " + name)
		_check(int(raw.samples) == frames + 1, "Endpoint-inclusive samples " + name)
		var position_counts: Dictionary = {}
		var rotation_counts: Dictionary = {}
		for track: Dictionary in raw.tracks:
			var pc: int = track.positions_raw.size()
			var rc: int = track.rotations_raw.size()
			_check(pc in [1, frames + 1] and rc in [1, frames + 1], "Static or full sample channel " + name + ":" + str(track.name))
			position_counts[pc] = int(position_counts.get(pc, 0)) + 1
			rotation_counts[rc] = int(rotation_counts.get(rc, 0)) + 1
		var hz := float(frames) / duration
		max_hz_error = maxf(max_hz_error, absf(hz - 30.0))
		_check(absf(hz - 30.0) < 0.00001, "Header supports nominal 30 Hz " + name)
		var catalog_row: Dictionary = settings.get(name, {})
		_check(not catalog_row.is_empty(), "Original catalog coverage " + name)
		_check(absf(float(catalog_row.get("duration", -1)) - duration) < 0.000001 and int(catalog_row.get("frames", -1)) == frames, "Catalog agrees with binary " + name)
		var times: Array[float] = []
		for index in frames + 1:
			times.append(float(index) * duration / float(frames))
		raw_sources[name] = {
			"name": name, "binary_path": binary_path, "binary_sha256": input_hashes[binary_path],
			"decoded_json_sha256": input_hashes[RAW.path_join(file)], "duration_seconds": duration,
			"frame_intervals": frames, "endpoint_inclusive_samples": int(raw.samples), "bone_channels": bones,
			"sample_rate_from_header_hz": hz, "nominal_sample_rate_hz": 30,
			"source_key_times_seconds": times, "position_channel_sample_counts": position_counts,
			"rotation_channel_sample_counts": rotation_counts,
			"original_catalog_settings_raw": catalog_row.get("settings", []),
			"original_catalog_settings_decoded": _settings(catalog_row.get("settings", [])),
			"retarget_resources": [], "mapped_logical_routes": [],
		}
	_check(raw_sources.size() == 264, "All 264 decoded SEAL clips")
	for directory: String in SOURCE_DIRS:
		for file: String in DirAccess.get_files_at(directory):
			if file.ends_with(".tres"):
				_resource(directory.path_join(file))
	var saved: Dictionary = _json(MAP)
	var profile = Profile.new()
	profile.load_project_map(MAP)
	var routes: Array = []
	for logical: StringName in profile.clip_paths:
		var original_path := String(profile.clip_paths[logical])
		var alias := profile.alias_source(logical)
		var effective_path := String(profile.clip_paths.get(alias, original_path)) if alias != &"" else original_path
		var record := _resource(effective_path)
		var dependencies := _dependencies(effective_path, [])
		for source_name: String in dependencies:
			if raw_sources.has(source_name):
				raw_sources[source_name].mapped_logical_routes.append(String(logical))
		var row := {"logical_clip": String(logical), "declared_path": original_path,
			"alias_source": String(alias), "effective_saved_resource_path": effective_path,
			"source_dependencies": dependencies, "resource_duration_seconds": record.get("duration_seconds"),
			"state_rule": profile.state_rules.get(logical, profile.state_rules.get(String(logical), {})),
			"configured_jump_timeline": profile.source_jump.get("clips", {}).get(String(logical), {}),
			"status": "saved_route_not_proof_of_state_activation"}
		var comparisons: Array = []
		for source_name: String in dependencies:
			if raw_sources.has(source_name) and record.has("duration_seconds"):
				comparisons.append({"source_name": source_name, "source_duration_seconds": raw_sources[source_name].duration_seconds,
					"saved_minus_source_seconds": float(record.duration_seconds) - float(raw_sources[source_name].duration_seconds)})
		row["source_duration_comparisons"] = comparisons
		routes.append(row)
	var weapons := _weapons(profile)
	var native_count := 0
	var max_reference_error := 0.0
	for name: String in raw_sources:
		var source: Dictionary = raw_sources[name]
		for path: String in resources:
			var record: Dictionary = resources[path]
			if record.get("source_name", "") == name:
				source.retarget_resources.append(path)
		var native_path := SOURCE_DIRS[1].path_join(name + ".tres") if name.begins_with("seal_fp_") or name.begins_with("seal_pfp_") else SOURCE_DIRS[0].path_join(name + ".tres")
		_check(resources.has(native_path), "Native reference present " + name)
		if resources.has(native_path):
			native_count += 1
			var duration_error := absf(float(resources[native_path].duration_seconds) - float(source.duration_seconds))
			max_reference_error = maxf(max_reference_error, duration_error)
			_check(duration_error < 0.00001, "Native reference retains duration " + name)
	var summary := {"decoded_seal_clips": raw_sources.size(), "binary_headers_verified": raw_sources.size(),
		"nominal_source_rate_hz": 30, "maximum_header_rate_error_hz": max_hz_error,
		"native_references_verified": native_count, "maximum_native_duration_error_seconds": max_reference_error,
		"inspected_resources": resources.size(), "canonical_logical_routes": routes.size(),
		"weapon_timing_profiles": weapons.size(), "failures": failures}
	var report := {"schema_version": 1, "created_at_utc": Time.get_datetime_string_from_system(true),
		"engine": Engine.get_version_info(), "summary": summary, "sources": raw_sources,
		"resources": resources, "mapped_routes": routes, "weapon_reload_timing": weapons,
		"canonical_locomotion_profile": profile.locomotion, "canonical_transition_profile": profile.transitions,
		"canonical_source_jump_profile": profile.source_jump, "canonical_state_rules": profile.state_rules,
		"locomotion_pre_graph_rate_examples": _rate_examples(profile),
		"saved_family_slots": saved.get("family_animation_slots", {}),
		"reload_stance_blend_profile": _json("res://config/reload_stance_blend.json"),
		"limitations": ["Primary MOTION_P SEAL archive only; not every mission bank.",
			"30 Hz comes from binary duration/frame intervals and sample count; it is not a runtime/render frame rate.",
			"Original catalog playback, BlendTime, NoFire, callback and velocity fields are decoded values, not recovered execution semantics.",
			"Saved resources and route definitions do not prove a runtime state plays; no main render is performed here.",
			"Graph direction/microstep modifiers, cyclic blends, phase seeks and weapon timing can change wall-clock playback.",
			"Reload ratios are derived from the actual normalized weapon contract and saved selected take; no ammo/gameplay timing is modified.",
			"Source jump windows are normalized authoring timelines driven by CharacterBody phase, not original wall-clock playback."]}
	# Protect against an unnoticed concurrent input change during the snapshot.
	for path: String in input_hashes:
		_check(FileAccess.get_sha256(path) == input_hashes[path], "Input unchanged during snapshot " + path)
	report["input_sha256"] = input_hashes
	if failures.is_empty() and not output.is_empty():
		_check(not FileAccess.file_exists(output), "Output appeared during audit; refusing overwrite")
		if failures.is_empty():
			var file := FileAccess.open(output, FileAccess.WRITE)
			_check(file != null, "Open new report")
			if file != null:
				file.store_string(JSON.stringify(report, "\t") + "\n")
				file.close()
				print("SOURCE_ANIMATION_TIMING report=", ProjectSettings.globalize_path(output))
	_finish(summary)


func _resource(path: String) -> Dictionary:
	if resources.has(path):
		return resources[path]
	if not FileAccess.file_exists(path):
		_check(false, "Missing mapped resource " + path)
		return {}
	_track_input(path)
	var resource := load(path)
	var animation := resource as Animation
	var instance: Node
	var selected_name := ""
	if resource is PackedScene:
		instance = (resource as PackedScene).instantiate()
		var player: AnimationPlayer = asset_reader._find_animation_player(instance)
		if player != null:
			selected_name = String(asset_reader._select_source_animation_name(player))
			if not selected_name.is_empty():
				animation = player.get_animation(selected_name)
	if animation == null:
		_check(false, "No animation in mapped resource " + path)
		if instance != null: instance.free()
		return {}
	var key_times: Dictionary = {}
	var counts: Dictionary = {}
	for track in animation.get_track_count():
		var count := animation.track_get_key_count(track)
		counts[count] = int(counts.get(count, 0)) + 1
		for key in count:
			key_times[animation.track_get_key_time(track, key)] = true
	var times := key_times.keys()
	times.sort()
	var deltas: Array[float] = []
	for index in range(1, times.size()):
		deltas.append(float(times[index]) - float(times[index - 1]))
	var record := {"path": path, "sha256": input_hashes[path], "selected_scene_animation": selected_name,
		"duration_seconds": animation.length, "loop_mode": animation.loop_mode,
		"track_count": animation.get_track_count(), "track_key_count_histogram": counts,
		"distinct_key_times_seconds": times, "minimum_key_interval_seconds": deltas.min() if not deltas.is_empty() else null,
		"maximum_key_interval_seconds": deltas.max() if not deltas.is_empty() else null}
	for key in ["seal_reference", "source_name", "source_sha256", "source_static", "source_coverage", "source_asset", "seal_composite_base", "source_settings"]:
		if animation.has_meta(key): record[key] = animation.get_meta(key)
	if animation.has_meta("source_window"):
		var window: Vector2 = animation.get_meta("source_window")
		record["source_window_seconds"] = [window.x, window.y]
	resources[path] = record
	if instance != null: instance.free()
	return record


func _dependencies(path: String, visited: Array) -> Array:
	if path in visited:
		_check(false, "Cyclic source provenance " + path)
		return []
	var record := _resource(path)
	var result: Array = []
	for key in ["source_name", "seal_composite_base"]:
		if record.has(key) and not record[key] in result: result.append(record[key])
	if record.has("source_asset"):
		for name: String in _dependencies(String(record.source_asset), visited + [path]):
			if not name in result: result.append(name)
	return result


func _weapons(profile) -> Array:
	var result: Array = []
	for file: String in DirAccess.get_files_at("res://config/weapons"):
		if not file.ends_with(".json") or file == "operator_loadout.json": continue
		var path := "res://config/weapons/" + file
		var raw: Dictionary = _json(path)
		if not raw.has("weapon_id"): continue
		var config: Dictionary = WeaponContract.load_config(path)
		var handling: Dictionary = config.get("handling_profile", {})
		var duration := clampf(float(config.get("ballistics", {}).get("reload_duration_seconds", handling.get("reload_duration_seconds", 1.75))), 0.25, 10.0)
		var slots: Dictionary = handling.get("animation_slots", {})
		var rows: Array = []
		for posture: String in ["STANDING", "CROUCHED", "PRONE"]:
			var slot := "reload_" + posture.to_lower()
			var clip := StringName(slots.get(slot, ""))
			if clip == &"" or not profile.clip_paths.has(clip): clip = profile.resolve_semantic_action(&"reload", StringName(posture))
			var record := _resource(String(profile.clip_paths[clip])) if profile.clip_paths.has(clip) else {}
			var source_length := float(record.get("duration_seconds", 0.0))
			var settled_idle := clip == &"pistol_reload_hold_prone" and not bool(record.get("seal_reference", false))
			var length := 1.0 if settled_idle else source_length
			var rate := clampf(length / duration, 0.25, 3.0)
			rows.append({"posture": posture, "clip": String(clip), "saved_take_duration_seconds": source_length,
				"runtime_settled_idle": settled_idle, "animation_duration_seconds_for_action": length,
				"target_reload_duration_seconds": duration, "clamped_playback_multiplier": rate,
				"expected_action_duration_seconds": length / rate, "speed_clamp_changes_target": absf(length / rate - duration) > 0.00001,
				"saved_reload_visual_events": handling.get("reload_visuals", {}).get(slot, {}).get("events", {})})
		result.append({"weapon_id": config.get("weapon_id"), "config_path": path,
			"family": handling.get("family"), "reload_duration_seconds": duration, "postures": rows})
	return result


func _rate_examples(profile) -> Array:
	var result: Array = []
	for entry in [["STANDING", 6.5, 1.0], ["STANDING", 6.25, 1.0], ["STANDING", 2.15, 1.0], ["STANDING", 2.15, 0.0], ["CROUCHED", 2.6, 1.0], ["PRONE", 1.25, 1.0]]:
		result.append({"posture": entry[0], "actual_speed_mps": entry[1], "full_gait_weight": entry[2],
			"nominal_speed_mps": profile.nominal_speed(StringName(entry[0]), entry[2]),
			"profile_playback_multiplier": profile.playback_rate(entry[1], StringName(entry[0]), entry[2])})
	return result


func _settings(raw: Variant) -> Dictionary:
	var result := {}
	if not raw is Array:
		return result
	for index in range(0, raw.size() - 1, 2):
		var value: Variant = raw[index + 1]
		result[str(raw[index])] = value[0] if value is Array and value.size() == 1 else value
	return result


func _track_input(path: String) -> void:
	if not input_hashes.has(path): input_hashes[path] = FileAccess.get_sha256(path)


func _json(path: String) -> Variant:
	_track_input(path)
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _check(ok: bool, reason: String) -> void:
	if not ok and not reason in failures: failures.append(reason)


func _finish(summary: Dictionary) -> void:
	print("SOURCE_ANIMATION_TIMING ", "PASS " if failures.is_empty() else "FAIL ", JSON.stringify(summary), " failures=", failures)
	quit(0 if failures.is_empty() else 1)
