extends "res://tools/rifle_reference_visual_probe.gd"
## Saved public IDs through the same Gunsmith/weapon contract used by main.
const Contract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const Visual := preload("res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd")
const Resolver := preload("res://scripts/labs/gunsmith2/weapon_visual_rig_resolver.gd")
const Editor := preload("res://scripts/labs/gunsmith/gunsmith_recom_catalog_adapter.gd")
const Rounds := preload("res://scripts/network/socom_round_weapon_rules.gd")
const Policy := preload("res://scripts/weapons/source_firearm_policy.gd")
var checks := 0

func _run() -> void:
	if capture and DisplayServer.get_name() == "headless":
		failures.append("Capture requires native display")
		_finish()
		return
	var manifest := _read("res://config/public_iso_weapon_migration.json")
	var ids: Array = _read("res://config/weapon_roster_extensions.json").public_roster.keys()
	_expect(manifest.entries.size() == 12, "all twelve public assignments")
	_expect(Rounds.firearm_pool().size() == 12, "round pool unchanged")
	for entry: Dictionary in manifest.entries:
		var path := "res://config/weapons/" + String(entry.id) + ".json"
		var raw := _read(path)
		var legacy := raw.duplicate(true)
		legacy.visual_rig_id = entry.previous_resolved_rig_id
		var previous := Resolver.resolve_for_presentation(legacy)
		var old_normalized := Contract.normalize_config(legacy, path)
		var config := Contract.load_config(path)
		var source := Contract.load_config("res://config/weapons/" + String(entry.source_id) + ".json")
		var document := _read("res://config/weapon_visual_rigs/" + String(entry.rig_id) + ".json")
		var validation := Visual.validate(document, true, entry.rig_id)
		_expect(validation.ok, "published rig " + entry.id + ": " + str(validation.errors))
		_expect(ids.has(entry.id) and Rounds.firearm_pool().has(entry.id), "existing selectable identity " + entry.id)
		_expect(config.model_fbx == entry.new_model and config.model_fbx == source.model_fbx, "source asset " + entry.id)
		_expect(config._visual_rig_id == entry.rig_id, "existing resolver consumed assignment " + entry.id)
		_expect(document.visual.handling_profile == previous.get("handling_profile", {}), "authored handling/clocks preserved " + entry.id)
		for key in ["weapon_id", "display_name", "ballistics", "fire_modes", "default_fire_mode", "burst_size", "reticle"]:
			_expect(config.get(key) == old_normalized.get(key), "protected " + entry.id + "/" + key)
		_expect(Policy.resolve(config) == Policy.resolve(old_normalized), "source firearm policy unchanged " + entry.id)
		var editable := Editor.load_editable_profile(entry.id)
		for key in ["model_fbx", "normalized_scale", "operator_mount", "grip_offset", "weapon_sockets"]:
			_expect(config.get(key) == source.get(key), "matching source calibration " + entry.id + "/" + key)
			if key != "weapon_sockets":
				_expect(editable.get(key) == config.get(key), "Gunsmith/runtime parity " + entry.id + "/" + key)
		for socket: String in config.weapon_sockets:
			var runtime_point := Contract.vector3_from_map(config.weapon_sockets[socket], Vector3.INF)
			var editor_point := Contract.vector3_from_map(editable.weapon_sockets.get(socket, {}), Vector3.INF)
			_expect(runtime_point.is_finite() and runtime_point.distance_to(editor_point) < .000001, "Gunsmith/runtime socket " + entry.id + "/" + socket)
	if not failures.is_empty():
		print("PUBLIC_ISO_MIGRATION FAIL ", failures)
		quit(1)
		return
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	ProjectSettings.set_setting("socom/session/public_training", true)
	root.size = Vector2i(1280, 800)
	scene = load("res://main.tscn").instantiate()
	scene.get_node("IndependentCameraRig").capture_mouse_on_ready = false
	root.add_child(scene)
	current_scene = scene
	player = scene.get_node("Player")
	player.set_local_input_enabled(false)
	await _frames(60)
	controller = scene.get_node("WeaponController")
	controller.set_input_enabled(false)
	driver = player.get_node("Mannequin/ProductionAnimation")
	_expect(driver.equipped_weapon_config.weapon_id == "m4a1", "default identity remains M4")
	_expect(driver.equipped_weapon_config.model_fbx == "res://assets/weapons/socom2_arsenal/s2_m4a1.scn", "default spawn already uses source M4")
	_install_fixture()
	for entry: Dictionary in manifest.entries:
		weapon_id = entry.id
		_expect(controller.apply_authorized_weapon_pickup("res://config/weapons/" + weapon_id + ".json"), "main equip " + weapon_id)
		await _frames(20)
		var mesh: Node = driver.weapon_node.find_child("WeaponMesh", true, false)
		var source := _read("res://config/weapons/" + String(entry.source_id) + ".json")
		_expect(mesh != null and mesh.get_meta("source_model", "") == source.source_asset.model, "actual held source mesh " + weapon_id)
		_expect(driver.weapon_node.is_visible_in_tree(), "held object visible " + weapon_id)
		_expect(not driver.weapon_node.has_node("CalibratedWeaponPivot/GripContactSurface"), "AGLS-specific contact proxy excluded " + weapon_id)
		for stance in [0, 1, 2]:
			_expect(player.call("_try_set_posture", stance), "stance " + weapon_id + "/" + str(stance))
			await _frames(100)
			if _request_shot():
				for frame in 32:
					await _frames(1)
					if frame in [0, 8, 30] and (not capture or weapon_id in ["m4a1", "ak-47", "mark_23"]):
						await _sample(weapon_id + "_" + str(stance) + "_fire_" + str(frame))
		print("PUBLIC_ISO_MAIN_EQUIP ", weapon_id, " model=", mesh.get_meta("source_model", ""))
	print("PUBLIC_ISO_MIGRATION ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " samples=", samples.size(), " ", failures)
	_finish()

func _read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
