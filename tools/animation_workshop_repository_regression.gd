extends SceneTree

const Repository := preload("res://scripts/labs/animation_workshop_repository.gd")

var failures: Array[String] = []
var repository = Repository.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var fbx_files: Dictionary = repository.scan_mixamo("res://assets/animations/mixamo")
	var authored_files: Dictionary = repository.scan_authored("res://assets/animations/authored")
	_expect(fbx_files.size() >= 100, "repository discovers the imported Mixamo catalog")
	var entries: Array[Dictionary] = repository.build_entries([], fbx_files, authored_files)
	_expect(entries.size() == fbx_files.size() + authored_files.size(), "repository builds one stable entry per discovered resource")
	var pistol_entries: Array[Dictionary] = repository.filter_entries(entries, "PISTOL")
	_expect(not pistol_entries.is_empty(), "repository owns category filtering")
	var reload_entries: Array[Dictionary] = repository.search_entries(entries, "reload")
	_expect(not reload_entries.is_empty(), "repository owns clip search")
	var suggested := repository.suggest_slot({
		"type": "FBX",
		"path": "res://assets/animations/mixamo/Shooter Pack/Firing Rifle.fbx",
	})
	_expect(suggested == "combat_fire", "repository owns deterministic runtime-route suggestions")
	var auto_map_entries: Array[Dictionary] = [{
		"type": "FBX",
		"path": "res://assets/animations/mixamo/Legacy/Walk Forward.fbx",
	}]
	var auto_map_result: Dictionary = repository.auto_map_result(auto_map_entries, {})
	_expect(
		auto_map_result.get("slots", {}).get("run_forward", "") == auto_map_entries[0]["path"],
		"repository preserves the Studio builder's broad walk fallback",
	)

	var state_path := "/private/tmp/animation_workshop_repository_states.json"
	var recipe_path := "/private/tmp/animation_workshop_repository_recipe.json"
	var highlight_path := "/private/tmp/animation_workshop_repository_highlights.json"
	var state_slots := {"idle_rifle": "res://clips/idle.fbx", "reload": "res://clips/reload.fbx"}
	_expect(repository.save_state_slots(state_path, state_slots), "repository saves runtime state mappings")
	_expect(repository.load_state_slots(state_path) == state_slots, "repository restores runtime state mappings")
	var recipe := {
		"full_body": "",
		"lower_body": "res://clips/run.fbx",
		"torso": "res://clips/aim.fbx",
		"left_arm": "",
		"right_arm": "",
		"head": "",
	}
	_expect(repository.save_layer_recipe(recipe_path, "CUSTOM_BODY", recipe), "repository saves body-layer recipes")
	_expect(repository.load_layer_recipe(recipe_path, recipe) == recipe, "repository restores body-layer recipes")
	var highlighted: Array[Dictionary] = [entries[0].duplicate(true)]
	_expect(repository.save_highlights(highlight_path, highlighted), "repository saves review highlights")
	var restored_highlights: Array[Dictionary] = repository.load_highlights(highlight_path, entries)
	_expect(
		restored_highlights.size() == 1
		and repository.entry_identity(restored_highlights[0]) == repository.entry_identity(highlighted[0]),
		"repository restores highlights by stable resource identity"
	)

	for path in [state_path, recipe_path, highlight_path]:
		DirAccess.remove_absolute(path)
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("ANIMATION_WORKSHOP_REPOSITORY_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("ANIMATION_WORKSHOP_REPOSITORY_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("ANIMATION_WORKSHOP_REPOSITORY_REGRESSION PASS")
		quit(0)
	else:
		print("ANIMATION_WORKSHOP_REPOSITORY_REGRESSION FAIL ", failures)
		quit(1)
