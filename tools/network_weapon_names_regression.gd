extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	ProjectSettings.set_setting("socom/session/tournament_mode", false)
	var scene := load("res://multiplayer_slice.tscn").instantiate() as Node3D
	root.add_child(scene)
	await process_frame
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapon_roster_extensions.json"))
	var names: Dictionary = registry.get("public_roster", {})
	_check(names.size() == 12, "all 12 public weapons are packaged")
	_check(names.get("ak-47") == "Bastion 7.62" and names.get("mark_23") == "Sentinel .45", "current codename registry")
	for id: String in names:
		# Exercise the actual round and warm-up handlers, not a fabricated HUD update.
		scene.receive_round_weapon(id, 1, [1])
		_check(scene.multiplayer_hud.loadout_card_hud.weapon_display_name == String(names[id]).to_upper(), "round name " + id)
		scene.receive_warmup_loadout({1: "m4a1"}, {})
		scene.receive_warmup_loadout({1: id}, {})
		_check(scene.multiplayer_hud.loadout_card_hud.weapon_display_name == String(names[id]).to_upper(), "warm-up name " + id)
		_check(scene.equipped_config.display_name == names[id], "shared weapon contract name " + id)
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapons/" + id + ".json"))
		var assigned: String = String(raw.get("visual_rig_id", ""))
		if not assigned.is_empty():
			_check(scene.equipped_config.get("_visual_rig_id", "") == assigned, "published visual rig retained " + id)
		var model: String = String(scene.equipped_config.get("model_fbx", ""))
		_check(not model.is_empty() and ResourceLoader.exists(model), "model packaged " + id)
		if not model.is_empty() and ResourceLoader.exists(model):
			_check(load(model) is PackedScene, "model loads without fallback " + id)
	scene.queue_free()
	await process_frame
	print("NETWORK_WEAPON_NAMES ", "PASS" if failures.is_empty() else "FAIL", " weapons=", names.size(), " ", failures)
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
