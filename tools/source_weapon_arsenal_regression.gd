extends SceneTree
const Catalog := preload("res://scripts/weapons/socom_weapon_catalog.gd")
const Contract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const VisualContract := preload("res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd")
const Editor := preload("res://scripts/labs/gunsmith/gunsmith_recom_catalog_adapter.gd")
const Economy := preload("res://scripts/economy/socom_economy_rules.gd")
const Rounds := preload("res://scripts/network/socom_round_weapon_rules.gd")
const Validator := preload("res://scripts/economy/socom_purchase_validator.gd")
const Policy := preload("res://scripts/weapons/source_firearm_policy.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Catalog.SOURCE_ARSENAL_PATH))
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(recipe.manifest))
	var model_names: Array[String] = []
	for model: Dictionary in source.models: model_names.append(model.name)
	var covered: Array[String] = []
	var ids := Catalog.source_arsenal_ids()
	_expect(ids.size() == 43, "43 explicit selections")
	_expect(Catalog.get_all_weapons().size() == 106, "63 original catalog records plus 43 additions")
	_expect(Rounds.firearm_pool().size() == 12, "competitive pool unchanged")
	for entry: Dictionary in recipe.entries:
		var id := String(entry.id)
		_expect(model_names.has(entry.model), "exact model " + id)
		if not covered.has(entry.model): covered.append(entry.model)
		var config := Contract.load_config("res://config/weapons/" + id + ".json")
		_expect(config.get("weapon_id") == id, "canonical identity " + id)
		_expect(config.get("model_fbx") == "res://assets/weapons/socom2_arsenal/" + id + ".scn", "canonical native model " + id)
		_expect(config.source_asset.source_manifest_sha256 == FileAccess.get_sha256(recipe.manifest), "source provenance " + id)
		var record := Catalog.get_weapon(id)
		_expect(Economy.is_armory_weapon(record), "visible selection " + id)
		_expect(not Rounds.firearm_pool().has(id), "no implicit competitive promotion " + id)
		_expect(Validator.validate(id, {"phase_open":true,"economy_enabled":true,"cash":0,"loadout":{}}).ok, "shared server selection validator " + id)
		_expect(config.display_name == record.display_name, "HUD/menu naming " + id)
		var editable := Editor.load_editable_profile(id)
		for key: String in recipe.alignment_defaults:
			_expect(config.support_hand_pose.get(key) == recipe.alignment_defaults[key], "saved alignment default " + id + "/" + key)
			_expect(editable.support_hand_pose.get(key) == config.support_hand_pose.get(key), "Gunsmith retains alignment policy " + id + "/" + key)
		for key in ["model_fbx", "normalized_scale", "operator_mount", "grip_offset"]:
			_expect(config[key] == editable[key], "Gunsmith/canonical " + id + "/" + key)
		for socket: String in config.weapon_sockets:
			var runtime_point := Contract.vector3_from_map(config.weapon_sockets[socket], Vector3.INF)
			var editor_point := Contract.vector3_from_map(editable.weapon_sockets.get(socket, {}), Vector3.INF)
			_expect(runtime_point.is_finite() and runtime_point.distance_to(editor_point) < 0.000001, "Gunsmith/canonical contact " + id + "/" + socket)
		var document := VisualContract.extract(config, id, 1, "published")
		_expect(VisualContract.validate(document, true).ok, "complete seven-socket contract " + id)
		_expect(Policy.resolve(config).policy_id == "project_hitscan", "asset-only addition does not claim original damage policy " + id)
		var node := (load(config.model_fbx) as PackedScene).instantiate() as Node3D
		_expect(node.get_meta("source_model", "") == entry.model, "saved model provenance " + id)
		var mesh_nodes := node.find_children("*", "MeshInstance3D", true, false)
		_expect(not mesh_nodes.is_empty(), "renderable mesh " + id)
		for mesh: MeshInstance3D in mesh_nodes:
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				_expect(material != null and material.albedo_texture != null, "embedded original texture " + id)
		var geometry := node.get_node("SourceGeometry") as Node3D
		var right := Contract.vector3_from_map(config.source_asset.right_contact_source_m, Vector3.ZERO)
		_expect((geometry.transform * right).length() < 0.00001, "right contact preserved by rigid rebase " + id)
		var part_count := 1 + int(bool(entry.get("scope", false))) + int(bool(entry.get("silencer", false)))
		_expect(node.get_meta("source_parts").size() == part_count, "single body LOD and selected attachments " + id)
		for part: String in node.get_meta("source_parts"):
			_expect(not "v0200" in part and not "thermal" in part, "no stacked low/thermal geometry " + id)
		node.free()
	_expect(covered.size() == 39, "all 39 distinct extracted firearm models represented")
	for model: String in recipe.non_firearm_models:
		_expect(model_names.has(model) and not covered.has(model), "explicit non-firearm/launcher exclusion " + model)
	_expect(covered.size() + recipe.non_firearm_models.size() == source.models.size(), "59-model census complete")
	if failures.is_empty() and "--runtime" in OS.get_cmdline_user_args():
		ProjectSettings.set_setting("socom/session/public_training", true)
		var game := (load("res://main.tscn") as PackedScene).instantiate()
		root.add_child(game)
		current_scene = game
		for frame in 20: await process_frame
		var driver := game.get_node("Player/Mannequin/ProductionAnimation")
		for id: String in ids:
			_expect(game.weapon_controller.apply_authorized_weapon_pickup("res://config/weapons/" + id + ".json"), "canonical equip " + id)
			for frame in 6: await process_frame
			_expect(driver.equipped_weapon_config.weapon_id == id, "actual driver consumes selection " + id)
			_expect(driver.weapon_node != null and driver.weapon_node.is_visible_in_tree(), "actual held weapon visible " + id)
			var mesh: Node = driver.weapon_node.find_child("WeaponMesh", true, false)
			_expect(mesh != null and mesh.get_meta("source_model", "") == Catalog.get_weapon(id).source_asset.model, "actual held source geometry " + id)
			print("SOURCE_ARSENAL_CANONICAL_EQUIP ", id)
		game.queue_free()
		await process_frame
	print("SOURCE_WEAPON_ARSENAL_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " ", failures)
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
