class_name SocomAnimationWorkshopRepository
extends RefCounted

## Owns Animation Workshop catalog discovery and project-file persistence.
## The scene controller remains responsible for preview/playback and UI only.

const SLOT_TARGETS: Dictionary = {
	"idle_rifle": ["Lite Rifle Pack/idle", "Rifle 8-Way Locomotion Pack/idle", "idle"],
	"aim_idle": ["Shooter Pack/rifle aiming idle", "aiming idle"],
	"run_forward": ["Lite Rifle Pack/run forward", "run forward"],
	"run_backward": ["Lite Rifle Pack/run backward", "run backward"],
	"run_left": ["Lite Rifle Pack/run left", "run left"],
	"run_right": ["Lite Rifle Pack/run right", "run right"],
	"run_forward_left": ["Lite Rifle Pack/run forward left", "run forward left"],
	"run_forward_right": ["Lite Rifle Pack/run forward right", "run forward right"],
	"run_back_left": ["Lite Rifle Pack/run backward left", "run backward left"],
	"run_back_right": ["Lite Rifle Pack/run backward right", "run backward right"],
	"idle_crouch": ["idle crouching", "crouch idle"],
	"crouch_forward": ["walk crouching forward"],
	"crouch_backward": ["walk crouching backward"],
	"crouch_left": ["walk crouching left"],
	"crouch_right": ["walk crouching right"],
	"crouch_forward_left": ["walk crouching forward left"],
	"crouch_forward_right": ["walk crouching forward right"],
	"crouch_back_left": ["walk crouching backward left"],
	"crouch_back_right": ["walk crouching backward right"],
	"idle_prone": ["Prone Firing Rifle", "Prone Idle"],
	"prone_forward": ["Prone Forward", "Crawl Forward"],
	"prone_backward": ["Moving Backward In Prone Position", "Prone Backward"],
	"prone_turn_left": ["Prone Left Turn", "Prone Turn Left"],
	"prone_turn_right": ["Prone Right Turn", "Prone Turn Right"],
	"prone_fire": ["Prone Firing Rifle", "Prone Fire"],
	"prone_reload": ["Prone Reloading", "Prone Reload"],
	"dive_roll": ["Running Dive Roll", "Dive Roll"],
	"roll": ["Run To Rolling", "Roll"],
	"jump_up": ["jump up"],
	"jump_loop": ["jump loop"],
	"jump_down": ["jump down"],
	"combat_fire": ["firing rifle"],
	"reload": ["Reloading", "Reload"],
	"start_forward": ["Start Walking"],
	"start_backward": ["start walking backwards"],
	"stop_forward": ["stop walking"],
	"stop_backward": ["walk backwards stop"],
	"run_to_stop": ["Run To Stop"],
	"crouch_start": ["Rifle Crouch Idle To Walk"],
	"crouch_stop": ["Crouch Stop Walking"],
	"turn_90_left": ["turn 90 left"],
	"turn_90_right": ["turn 90 right"],
}

## The one-click builder intentionally has broader fallbacks than the suggestion
## engine. Keep this table separate so extracting the repository cannot silently
## change a user's existing Studio workflow.
const AUTO_MAP_TARGETS: Dictionary = {
	"idle_rifle": ["Lite Rifle Pack/idle", "Rifle 8-Way Locomotion Pack/idle", "idle"],
	"aim_idle": ["Shooter Pack/rifle aiming idle", "aiming idle", "idle"],
	"run_forward": ["Lite Rifle Pack/run forward", "run forward", "walk forward"],
	"run_backward": ["Lite Rifle Pack/run backward", "run backward", "walk backward"],
	"run_left": ["Lite Rifle Pack/run left", "run left", "walk left"],
	"run_right": ["Lite Rifle Pack/run right", "run right", "walk right"],
	"run_forward_left": ["Lite Rifle Pack/run forward left", "run forward left"],
	"run_forward_right": ["Lite Rifle Pack/run forward right", "run forward right"],
	"run_back_left": ["Lite Rifle Pack/run backward left", "run backward left"],
	"run_back_right": ["Lite Rifle Pack/run backward right", "run backward right"],
	"idle_crouch": ["Rifle 8-Way Locomotion Pack/idle crouching", "idle crouching", "crouch idle"],
	"crouch_forward": ["Rifle 8-Way Locomotion Pack/walk crouching forward", "walk crouching forward"],
	"crouch_backward": ["Rifle 8-Way Locomotion Pack/walk crouching backward", "walk crouching backward"],
	"crouch_left": ["Rifle 8-Way Locomotion Pack/walk crouching left", "walk crouching left"],
	"crouch_right": ["Rifle 8-Way Locomotion Pack/walk crouching right", "walk crouching right"],
	"crouch_forward_left": ["Rifle 8-Way Locomotion Pack/walk crouching forward left"],
	"crouch_forward_right": ["Rifle 8-Way Locomotion Pack/walk crouching forward right"],
	"crouch_back_left": ["Rifle 8-Way Locomotion Pack/walk crouching backward left"],
	"crouch_back_right": ["Rifle 8-Way Locomotion Pack/walk crouching backward right"],
	"idle_prone": ["Prone Firing Rifle", "Prone Idle", "Prone Forward Stop"],
	"prone_forward": ["Prone Forward", "Crawl Forward"],
	"prone_backward": ["Moving Backward In Prone Position", "Prone Backward"],
	"prone_turn_left": ["Prone Left Turn", "Prone Turn Left"],
	"prone_turn_right": ["Prone Right Turn", "Prone Turn Right", "Prone Left Turn"],
	"prone_fire": ["Prone Firing Rifle", "Prone Fire"],
	"prone_reload": ["Prone Reloading", "Prone Reload"],
	"dive_roll": ["Running Dive Roll", "Dive Roll"],
	"roll": ["Run To Rolling", "Roll"],
	"jump_up": ["Rifle 8-Way Locomotion Pack/jump up", "jump up"],
	"jump_loop": ["Rifle 8-Way Locomotion Pack/jump loop", "jump loop"],
	"jump_down": ["Rifle 8-Way Locomotion Pack/jump down", "jump down"],
	"combat_fire": ["Shooter Pack/firing rifle", "firing rifle"],
	"reload": ["Reloading", "Reload"],
}


func scan_mixamo(root_path: String) -> Dictionary:
	var results: Dictionary = {}
	_scan_mixamo_recursive(root_path, results)
	return results


func scan_authored(directory_path: String) -> Dictionary:
	var results: Dictionary = {}
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return results
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".tres"):
			results[file_name.get_basename().capitalize()] = "%s/%s" % [
				directory_path,
				file_name,
			]
		file_name = directory.get_next()
	directory.list_dir_end()
	return results


func build_entries(
	baked_clips: Array[StringName],
	fbx_files: Dictionary,
	authored_files: Dictionary
) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for baked in baked_clips:
		entries.append({
			"name": baked,
			"key": str(baked),
			"display": str(baked),
			"type": "BAKED",
			"path": "",
		})
	for fbx_name in fbx_files.keys():
		var clean_key := (
			str(fbx_name)
			.replace("[", "")
			.replace("]", "")
			.replace(" ", "_")
			.replace("-", "_")
			.replace("(", "")
			.replace(")", "")
			.replace(".", "_")
			.to_lower()
		)
		entries.append({
			"name": StringName("dyn/" + clean_key),
			"key": clean_key,
			"display": fbx_name,
			"type": "FBX",
			"path": fbx_files[fbx_name],
		})
	for authored_name in authored_files.keys():
		var authored_key := "authored_" + str(authored_name).to_snake_case()
		entries.append({
			"name": StringName("dyn/" + authored_key),
			"key": authored_key,
			"display": "[Authored] " + str(authored_name),
			"type": "AUTHORED",
			"path": authored_files[authored_name],
		})
	return entries


func filter_entries(entries: Array[Dictionary], category: String) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for entry in entries:
		var display := str(entry.get("display", "")).to_lower()
		var include := false
		match category:
			"ALL":
				include = true
			"RIFLE LOCO":
				include = (
					("walk" in display or "run" in display or "sprint" in display or "strafe" in display)
					and not "crouch" in display
					and not "pistol" in display
				)
			"PISTOL":
				include = "pistol" in display
			"CROUCH & PRONE":
				include = "crouch" in display or "prone" in display or "kneel" in display or "crawl" in display
			"COMBAT & FIRE":
				include = "fire" in display or "aim" in display or "reload" in display or "shoot" in display or "throw" in display
			"AGILITY & DIVE":
				include = "dive" in display or "roll" in display or "jump" in display or "land" in display
			"DEATH & HIT":
				include = "death" in display or "hit" in display or "die" in display
			"AUTHORED":
				include = entry.get("type", "") in ["BAKED", "AUTHORED"]
		if include:
			filtered.append(entry)
	return entries.duplicate(true) if filtered.is_empty() else filtered


func search_entries(entries: Array[Dictionary], query: String) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	var normalized_query := query.strip_edges().to_lower()
	for entry in entries:
		if normalized_query.is_empty() or normalized_query in str(entry.get("display", "")).to_lower():
			filtered.append(entry)
	return filtered


func entry_identity(entry: Dictionary) -> String:
	var path := str(entry.get("path", ""))
	return path if not path.is_empty() else "%s:%s" % [
		str(entry.get("type", "")),
		str(entry.get("key", entry.get("name", ""))),
	]


func entry_index(entries: Array[Dictionary], entry: Dictionary) -> int:
	var identity := entry_identity(entry)
	for index in range(entries.size()):
		if entry_identity(entries[index]) == identity:
			return index
	return -1


func entry_for_path(entries: Array[Dictionary], resource_path: String) -> Dictionary:
	for entry in entries:
		if String(entry.get("path", "")) == resource_path:
			return entry
	return {}


func suggest_slot(entry: Dictionary) -> String:
	if str(entry.get("type", "")) != "FBX":
		return ""
	var path := str(entry.get("path", "")).to_lower()
	var best_slot := ""
	var best_score := -1
	for slot_key in SLOT_TARGETS.keys():
		for candidate in SLOT_TARGETS[slot_key]:
			var candidate_text := str(candidate).to_lower()
			if candidate_text in path and candidate_text.length() > best_score:
				best_slot = str(slot_key)
				best_score = candidate_text.length()
	return best_slot


func auto_map_slots(entries: Array[Dictionary], current_slots: Dictionary) -> Dictionary:
	return auto_map_result(entries, current_slots).get("slots", current_slots.duplicate(true))


func auto_map_result(entries: Array[Dictionary], current_slots: Dictionary) -> Dictionary:
	var mapped := current_slots.duplicate(true)
	var mapped_count := 0
	for slot_key in AUTO_MAP_TARGETS.keys():
		var found_path := ""
		for candidate in AUTO_MAP_TARGETS[slot_key]:
			var candidate_text := str(candidate).to_lower()
			for entry in entries:
				if str(entry.get("type", "")) != "FBX":
					continue
				var full_path := str(entry.get("path", "")).to_lower()
				if candidate_text in full_path:
					found_path = str(entry.get("path", ""))
					break
			if not found_path.is_empty():
				break
		if not found_path.is_empty():
			mapped[slot_key] = found_path
			mapped_count += 1
	return {
		"slots": mapped,
		"mapped_count": mapped_count,
		"target_count": AUTO_MAP_TARGETS.size(),
	}


func load_state_slots(path: String) -> Dictionary:
	var config := _load_json_dictionary(path)
	var clips: Variant = config.get("clips", {})
	return (clips as Dictionary).duplicate(true) if clips is Dictionary else {}


func save_state_slots(path: String, slots: Dictionary) -> bool:
	var config := _load_json_dictionary(path)
	if config.is_empty():
		config = {
			"version": 1,
			"description": "Gameplay state -> editable Mixamo FBX mapping.",
		}
	config["clips"] = slots.duplicate(true)
	return _save_json_dictionary(path, config)


func load_layer_recipe(path: String, defaults: Dictionary) -> Dictionary:
	var recipe := defaults.duplicate(true)
	var saved := _load_json_dictionary(path)
	var layers: Variant = saved.get("layers", {})
	if layers is Dictionary:
		for layer_key in recipe.keys():
			recipe[layer_key] = String((layers as Dictionary).get(layer_key, ""))
	return recipe


func save_layer_recipe(path: String, family: String, recipe: Dictionary) -> bool:
	return _save_json_dictionary(path, {
		"version": 1,
		"weapon_family": family,
		"layers": recipe,
		"note": "Bone-masked animation sources. Gameplay aim remains authoritative over the final head and weapon pose.",
	})


func load_highlights(path: String, entries: Array[Dictionary]) -> Array[Dictionary]:
	var highlighted: Array[Dictionary] = []
	var saved := _load_json_dictionary(path)
	var selected: Variant = saved.get("selected_clips", [])
	if not selected is Array:
		return highlighted
	for raw_entry in selected:
		if not raw_entry is Dictionary:
			continue
		var index := entry_index(entries, raw_entry as Dictionary)
		if index >= 0:
			highlighted.append(entries[index].duplicate(true))
	return highlighted


func save_highlights(path: String, entries: Array[Dictionary]) -> bool:
	var selected_clips: Array[Dictionary] = []
	for raw_entry in entries:
		var entry := raw_entry.duplicate(true)
		selected_clips.append({
			"display": str(entry.get("display", "Animation clip")),
			"type": str(entry.get("type", "")),
			"key": str(entry.get("key", entry.get("name", ""))),
			"path": str(entry.get("path", "")),
			"suggested_slot": suggest_slot(entry),
		})
	return _save_json_dictionary(path, {
		"version": 1,
		"purpose": "User-selected animation candidates for Codex review and route assembly.",
		"selected_clips": selected_clips,
	})


func _scan_mixamo_recursive(directory_path: String, results: Dictionary) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if directory.current_is_dir() and not file_name.begins_with("."):
			_scan_mixamo_recursive(directory_path + "/" + file_name, results)
		elif file_name.ends_with(".fbx") and not file_name.begins_with("."):
			var folder := directory_path.get_file()
			var tag := ""
			if "Pistol" in folder:
				tag = "[Pistol] "
			elif "Locomotion" in folder or "Lite" in folder:
				tag = "[Rifle] "
			elif "Shooter" in folder:
				tag = "[Shooter] "
			results[tag + file_name.get_basename().capitalize()] = directory_path + "/" + file_name
		file_name = directory.get_next()
	directory.list_dir_end()


func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _save_json_dictionary(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "  "))
	return true
