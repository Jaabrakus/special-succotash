extends SceneTree

## Read-only source census. Resolvers are exercised; no AnimationTree is advanced.
## --json emits the full report, --candidates emits every unreferenced source take.
const Profile := preload("res://scripts/player/operator_animation_profile.gd")
const Graph := preload("res://scripts/player/operator_locomotion_blend_tree.gd")
const Actions := preload("res://scripts/player/operator_animation_driver_actions.gd")
const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const SOURCE_DIRS := ["res://assets/animations/seal_reference", "res://assets/animations/seal_firing_reference"]
const WEAPONS := ["m4a1", "ak-47", "mark_23"]
const POSTURES := [&"STANDING", &"CROUCHED", &"PRONE"]
var profile = Profile.new()
var available: Dictionary = {}
var resources: Dictionary = {}
var logical_resources: Dictionary = {}
var references: Dictionary = {}
var source_library: Dictionary = {}
var failures: Array[String] = []
var routes: Array[Dictionary] = []
var configured_graph_policies: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument not in ["--json", "--candidates"]:
			push_error("Unknown argument: " + argument)
			quit(2)
			return
	var map_hash := FileAccess.get_sha256(Profile.MAP_PATH)
	profile.load_project_map()
	for clip: StringName in profile.clip_paths:
		var path := String(profile.clip_paths[clip])
		if ResourceLoader.exists(path):
			available[clip] = true
		logical_resources[clip] = _resource(path)
	# Match AssetRuntime's overwrite order. These are saved derivations, not
	# skeleton evaluation; preserve both the declared path and effective source.
	for mapping: Dictionary in [profile.mirrored_clips, profile.leg_mirrored_clips, profile.clip_aliases]:
		for target: StringName in mapping:
			var source := StringName(mapping[target])
			if available.has(source) and logical_resources.has(source):
				logical_resources[target] = logical_resources[source]
				available[target] = true
	for clip: StringName in logical_resources:
		_reference(logical_resources[clip], "logical:" + String(clip))
	for directory: String in SOURCE_DIRS:
		for file: String in DirAccess.get_files_at(directory):
			if not file.ends_with(".tres"):
				continue
			var record := _resource(directory.path_join(file))
			var source_name := String(record.get("source_name", ""))
			if source_name.is_empty():
				continue
			if not source_library.has(source_name):
				source_library[source_name] = {"name": source_name, "category": _category(source_name), "resources": []}
			source_library[source_name].resources.append(record.path)
	for weapon: String in WEAPONS:
		_weapon_routes(weapon)
	var death := _json("res://config/operator_death.json")
	for posture: StringName in POSTURES:
		_route("ALL", "death/" + String(posture), StringName(death.get(String(posture).to_lower() + "_clip", "")), "saved_death_contract")
	var climb := _json("res://config/ledge_climb.json")
	for slot: String in climb.get("presentation_clips", {}):
		_route("ALL", "traversal/" + slot, StringName(climb.presentation_clips[slot]), "saved_traversal_contract")
	var unreferenced: Array[Dictionary] = []
	var categories: Dictionary = {}
	var source_names := source_library.keys()
	source_names.sort()
	for source_name: String in source_names:
		if not references.has(source_name):
			var candidate: Dictionary = source_library[source_name]
			unreferenced.append(candidate)
			categories[candidate.category] = int(categories.get(candidate.category, 0)) + 1
	var fallback_routes: Array[Dictionary] = []
	var selected_source_routes := 0
	for row: Dictionary in routes:
		if row.resource.get("source_dependencies", []).is_empty():
			fallback_routes.append(row)
		else:
			selected_source_routes += 1
	if FileAccess.get_sha256(Profile.MAP_PATH) != map_hash:
		failures.append("Animation map changed during census; rerun for a coherent snapshot")
	var summary := {
		"configured_logical_clips": profile.clip_paths.size(),
		"available_saved_resources": available.size(),
		"distinct_source_library_takes": source_library.size(),
		"examined_routes": routes.size(), "routes_with_source_provenance": selected_source_routes,
		"routes_without_source_provenance": fallback_routes.size(),
		"unreferenced_source_takes": unreferenced.size(), "unreferenced_categories": categories,
		"evaluated_runtime_routes": 0, "failures": failures,
	}
	var report := {
		"schema_version": 1, "engine": Engine.get_version_info(), "summary": summary,
		"evidence_level": "saved_resources_and_canonical_resolvers_only",
		"runtime_evaluated": false, "source_parity_verified": false,
		"animation_map_sha256": map_hash,
		"canonical_scene": "res://main.tscn", "configured_routes": routes,
		"fallback_or_unknown_provenance_routes": fallback_routes,
		"unreferenced_source_candidates": unreferenced, "source_references": references,
		"configured_graph_policies": configured_graph_policies,
		"logical_resources": logical_resources,
		"limitations": [
			"A selected resolver result does not prove active graph weight, bone evaluation or original-game timing.",
			"Available means ResourceLoader.exists, not successful import, retarget or frame evaluation.",
			"Source provenance follows declared metadata, including composite bases and source windows; it does not prove unmodified poses.",
			"Unreferenced means absent from configured logical provenance and inspected auxiliary contracts, not unusable or unsupported.",
			"Only M4A1, AK-47 and Mark 23 resolver scenarios are sampled; logical census covers the full shared map.",
			"Missing or external source provenance is an audit finding, not a failed source-parity test.",
		],
	}
	if "--json" in OS.get_cmdline_user_args():
		print("SOURCE_ANIMATION_COVERAGE_JSON=", JSON.stringify(report))
	else:
		print("SOURCE_ANIMATION_COVERAGE ", JSON.stringify(summary))
		for row: Dictionary in fallback_routes:
			print("COVERAGE_GAP ", row.weapon, " ", row.route, " -> ", row.clip, " ", row.resource.get("path", "MISSING"))
		if "--candidates" in OS.get_cmdline_user_args():
			for candidate: Dictionary in unreferenced:
				print("SOURCE_CANDIDATE ", candidate.category, " ", candidate.name)
	quit(0 if failures.is_empty() else 1)


func _weapon_routes(weapon: String) -> void:
	var config: Dictionary = WeaponContract.load_config("res://config/weapons/" + weapon + ".json")
	var handling: Dictionary = config.get("handling_profile", {})
	var family := StringName(handling.get("family", ""))
	var graph = Graph.new()
	graph.profile = profile
	graph.weapon_handling_profile = handling
	graph.modern_enabled = true
	graph._configure_source_controller(available)
	configured_graph_policies[weapon] = {
		"source_controller_active": graph.source_controller_active,
		"native_range_count": graph.source_policy.entries.size(),
		"runtime_evaluated": false,
	}
	var actions = Actions.new()
	actions.animation_profile = profile
	actions.equipped_weapon_handling_profile = handling
	actions.equipped_weapon_family = family
	actions.available_clips = available
	for posture: StringName in POSTURES:
		actions.posture = posture
		for action: StringName in [&"fire", &"reload", &"grenade_full", &"grenade_quick"]:
			_route(weapon, "semantic/" + String(action) + "/" + String(posture), actions.resolve_semantic_action(action), "canonical_action_resolver")
		for event: StringName in [&"FIRE_ACCEPTED", &"RELOAD_STARTED", &"WEAPON_EQUIPPED"]:
			_route(weapon, "event/" + String(event) + "/" + String(posture), profile.resolve_animation_event(event, posture, family), "configured_event_resolver_not_action_dispatch")
		var suffix := String(posture).to_lower()
		var idle: StringName = &"idle_prone" if posture == &"PRONE" else (&"idle_crouch" if posture == &"CROUCHED" else &"idle_rifle")
		if family == &"TWO_HAND_PISTOL" and posture != &"PRONE":
			idle = &"pistol_idle_kneeling" if posture == &"CROUCHED" else &"pistol_idle"
		for slot: String in ["idle_" + suffix, "ready_" + suffix]:
			_route(weapon, slot, graph._weapon_action_clip(slot, idle, available), "canonical_graph_slot_resolver")
		for side: String in ["left", "right"]:
			var path := String(profile.authored_peek.get("families", {}).get(String(family), {}).get(String(posture), {}).get(side, ""))
			var resource := _resource(path)
			_reference(resource, "peek:" + String(family) + "/" + String(posture) + "/" + side)
			routes.append({"weapon": weapon, "route": "peek/" + String(posture) + "/" + side, "clip": "", "selection": "saved_posture_layer_source", "runtime_evaluated": false, "resource": resource})
	var prefixes: Array[StringName] = [&"walk", &"run", &"crouch"]
	if graph.source_controller_active:
		prefixes.insert(1, &"jog")
	for prefix: StringName in prefixes:
		for firing: bool in [false, true]:
			if firing and not graph.source_firing_enabled():
				continue
			var space: AnimationNodeBlendSpace2D = graph._direction_space(prefix, available, firing)
			for index in space.get_blend_point_count():
				var node := space.get_blend_point_node(index) as AnimationNodeAnimation
				var point := space.get_blend_point_position(index)
				_route(weapon, "locomotion/" + String(prefix) + ("/ready" if firing else "/base") + "/" + str(point), node.animation, "canonical_blendspace_point_not_evaluated")
	var prone: AnimationNodeBlendSpace1D = graph._prone_direction_space(available)
	for index in prone.get_blend_point_count():
		var node := prone.get_blend_point_node(index) as AnimationNodeAnimation
		_route(weapon, "locomotion/prone/" + str(prone.get_blend_point_position(index)), node.animation, "canonical_blendspace_point_not_evaluated")
	for clip: StringName in [&"jump_up", &"jump_up_standing", &"jump_loop", &"jump_down"]:
		_route(weapon, "jump/" + String(clip), graph._weapon_action_clip(String(clip), clip, available), "canonical_graph_slot_resolver")
	for clip: StringName in [&"start_forward", &"start_backward", &"stop_forward", &"stop_backward", &"run_to_stop", &"crouch_start", &"crouch_stop", &"turn_90_left", &"turn_90_right", &"crouch_to_stand", &"crouch_to_prone"]:
		_route(weapon, "transition_candidate/" + String(clip), clip, "saved_transition_candidate_not_activation_proof")
	actions.free()


func _route(weapon: String, route: String, clip: StringName, selection: String) -> void:
	routes.append({"weapon": weapon, "route": route, "clip": String(clip), "selection": selection,
		"runtime_evaluated": false, "declared_path": String(profile.clip_paths.get(clip, "")),
		"resource": logical_resources.get(clip, {"path": "", "status": "missing_logical_clip", "source_dependencies": []})})


func _resource(path: String, visited: Array[String] = []) -> Dictionary:
	if resources.has(path):
		return resources[path]
	if path in visited:
		failures.append("Source provenance cycle: " + path)
		return {}
	var result := {"path": path, "status": "missing_resource", "source_dependencies": []}
	if path.is_empty() or not ResourceLoader.exists(path):
		resources[path] = result
		return result
	result.status = "external_or_unknown_provenance"
	if path.ends_with(".tres"):
		var animation := ResourceLoader.load(path, "Animation") as Animation
		if animation == null:
			failures.append("Not an Animation: " + path)
			return result
		result["duration_seconds"] = animation.length
		result["tracks"] = animation.get_track_count()
		for key: String in ["seal_reference", "source_name", "source_sha256", "source_coverage", "source_static", "source_asset", "seal_composite_base"]:
			if animation.has_meta(key):
				result[key] = animation.get_meta(key)
		for key: String in ["source_name", "seal_composite_base"]:
			var source_name := String(result.get(key, ""))
			if not source_name.is_empty() and source_name not in result.source_dependencies:
				result.source_dependencies.append(source_name)
		if animation.has_meta("source_asset"):
			var ancestry: Array[String] = visited.duplicate()
			ancestry.append(path)
			var parent := _resource(String(animation.get_meta("source_asset")), ancestry)
			for source_name: String in parent.get("source_dependencies", []):
				if source_name not in result.source_dependencies:
					result.source_dependencies.append(source_name)
		if animation.has_meta("source_window"):
			var window: Vector2 = animation.get_meta("source_window")
			result["source_window_seconds"] = [window.x, window.y]
		if not result.source_dependencies.is_empty():
			result.status = "declared_source_provenance"
	resources[path] = result
	return result


func _reference(record: Dictionary, reference: String) -> void:
	for source_name: String in record.get("source_dependencies", []):
		if not references.has(source_name):
			references[source_name] = []
		if reference not in references[source_name]:
			references[source_name].append(reference)


func _category(name: String) -> String:
	if name.begins_with("death_"): return "death"
	if "reload" in name: return "reload"
	if "lean" in name: return "lean"
	if "climb" in name or "hang" in name or "ladder" in name: return "traversal"
	if "jump" in name or "dive" in name: return "jump_dive"
	if "grenade" in name or "throw" in name: return "throw"
	if "2" in name and not name.ends_with("02"): return "transition"
	if "_fp_" in name or "_pfp_" in name or "recoil" in name: return "firing"
	return "other_locomotion_or_action"


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	failures.append("Invalid JSON: " + path)
	return {}
