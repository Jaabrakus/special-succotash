extends SceneTree

const Catalog := preload("res://scripts/weapons/socom_weapon_catalog.gd")
const Adapter := preload("res://scripts/labs/gunsmith/gunsmith_recom_catalog_adapter.gd")
const Contract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const Repository := preload("res://scripts/labs/gunsmith/gunsmith_weapon_profile_repository.gd")
const Rules := preload("res://scripts/network/socom_round_weapon_rules.gd")
const Validator := preload("res://scripts/economy/socom_purchase_validator.gd")
const CASES := {"m3_12_gauge": [180.0, 3.5, 12], "ta_12_gauge": [120.0, 4.0, 12], "12_gauge_pump": [80.0, 4.5, 8]}
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Catalog.CATALOG_PATH))
	var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Catalog.EXTENSIONS_PATH))
	var pool := Rules.firearm_pool()
	for record: Dictionary in baseline.weapons:
		var expected := record.duplicate(true)
		expected.merge(registry.get("metadata_overrides", {}).get(String(record.weapon_id), {}), true)
		_expect(Catalog.get_weapon(String(record.weapon_id)) == expected, "original preserved except explicit catalog metadata " + String(record.weapon_id))
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for frame in 40:
		await process_frame
	var controller := scene.get_node("WeaponController")
	var driver: Node = scene.get_node("Player/Mannequin").get("production_animation")
	var session := (load("res://multiplayer_slice.tscn") as PackedScene).instantiate()
	var server_ballistics := preload("res://scripts/weapons/weapon_ballistics.gd").new()
	for id: String in CASES:
		var path := Repository.profile_path(id)
		var raw := Repository.load_profile(id)
		var runtime := Contract.load_config(path)
		var editable := Adapter.load_editable_profile(id)
		_expect(Catalog.get_weapon(id).get("ballistics") == raw.ballistics, id + " catalog reads canonical data")
		_expect(runtime.ballistics == Contract.normalize_config(editable).ballistics, id + " editor/runtime parity")
		_expect(not pool.has(id), id + " excluded from random tournament pool")
		_expect(bool(Validator.validate(id, {"economy_enabled": false, "allow_training_prototypes": true}).get("ok", false)), id + " training selection")
		_expect(not bool(Validator.validate(id, {"economy_enabled": false}).get("ok", true)), id + " warmup does not offer unapproved prototypes")
		_expect(not bool(Validator.validate(id, {"economy_enabled": true, "cash": 99999, "phase_open": true}).get("ok", true)), id + " not offered for competitive purchase")
		_expect(bool(runtime.get("socket_contract_authored", false)), id + " calibrated contacts")
		_expect(not bool(raw.provenance.original_game_data_verified), id + " honest provenance")
		_expect(not bool(raw.audio_reference.runtime_enabled), id + " pending sound stays disabled")
		var saved := Adapter.decorate_saved_profile({"ballistics": {"damage": 17.0}}, id)
		_expect(float(saved.ballistics.damage) == 17.0, id + " save preserves tuning")
		_expect(saved.catalog_source == raw.catalog_source, id + " save preserves source")
		var metadata := {}
		Repository._preserve_unknown_top_level_fields(metadata, raw)
		_expect(metadata.provenance == raw.provenance, id + " repository retains provenance")
		var prepared := Repository.prepare_profile_for_save({"ballistics": {"damage": 17.0}}, raw)
		_expect(prepared.ballistics.damage == 17.0, id + " explicit edit wins")
		for field in ["pellet_count", "pellet_spread_deg", "pellet_damage", "reload_duration_seconds", "damage_falloff_end_m"]:
			_expect(prepared.ballistics[field] == raw.ballistics[field], id + " save preserves " + field)
		_expect(prepared.provenance == raw.provenance, id + " save keeps provenance")
		_expect(bool(controller.call("apply_authorized_weapon_pickup", path)), id + " canonical equip")
		var local: Node = controller.get("ballistics")
		session.call("_apply_ballistics_profile", server_ballistics, runtime)
		for consumer in [local, server_ballistics]:
			_expect(is_equal_approx(float(consumer.get("fire_interval")), 60.0 / CASES[id][0]), id + " cadence")
			_expect(int(consumer.get("pellet_count")) == 8, id + " pellet count")
			_expect(is_equal_approx(float(consumer.get("pellet_spread_deg")), 3.0), id + " pellet spread")
		_expect(int(controller.get("rounds_in_magazine")) == int(CASES[id][2]), id + " capacity")
		_expect(is_equal_approx(float(driver.call("weapon_reload_duration_seconds")), CASES[id][1]), id + " reload duration")
		for frame in 10:
			await process_frame
		if "--render" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/private/tmp/mixed-roster-%s.png" % id)
		print("MIXED WEAPON CHECK ", id, " RPM/reload/capacity=", CASES[id])
	server_ballistics.free()
	session.free()
	scene.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("MIXED_WEAPON_ROSTER_REGRESSION ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
