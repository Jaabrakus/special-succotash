extends SceneTree

const Driver = preload("res://scripts/player/operator_animation_driver.gd")
const Weapons = preload("res://scripts/weapons/weapon_rig_contract.gd")
var failures: Array[String] = []

func _initialize() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	_run.call_deferred()

func _run() -> void:
	var driver := Driver.new()
	root.add_child(driver)
	await process_frame
	driver.set_process(false)
	for gun in ["ak-47", "m4a1", "mark_23", "ak-47"]:
		check(driver.notify_weapon_equipped(Weapons.load_config("res://config/weapons/" + gun + ".json")), "equip " + gun)
		var graph = driver.locomotion_graph
		var tree: AnimationNodeBlendTree = driver.animation_tree.tree_root
		if gun == "mark_23":
			check(not graph.source_standing_fire_split and not tree.has_node(&"source_standing_alert"), "pistol unchanged")
			continue
		check(graph.source_standing_fire_split, "rifle split enabled")
		check(graph.is_source_clip(String(driver.animation_profile.clip_paths[&"seal_stand_alert02"])), "ready preserves source weapon strategy")
		check(tree.get_node(&"standing_idle_base").animation == &"idle_rifle", "unready standing uses original default Stand")
		check(driver.animation_player.get_animation(&"idle_rifle").get_meta("source_name", "") == "seal_stand", "idle resource retains original default provenance")
		check(tree.get_node(&"source_standing_alert").animation == &"seal_stand_alert02", "ready source")
		check(tree.get_node(&"source_standing_fire").animation == &"seal_fp_stand", "separate fire source")
		check(graph.source_standing_fire_weight == 0.0, "equip clears blend")
		graph.publish_source_standing_fire(false, 1.0 / 60.0)
		check(graph.source_standing_fire_weight == 0.0, "no shot stays ready")
		check(driver.notify_fired(), "accepted shot remains routed")
		for frame in 45:
			graph.publish_source_standing_fire(driver._fire_upper_body_selected(), 1.0 / 60.0)
		check(graph.source_standing_fire_weight > 0.99, "shot selects fire")
		driver.clear_fire_ready_aim()
		for frame in 75:
			graph.publish_source_standing_fire(false, 1.0 / 60.0)
		check(graph.source_standing_fire_weight == 0.0, "recovers ready")
		check(driver.animation_profile.family_animation_slots.TWO_HAND_RIFLE.ready_standing_moving == "seal_fp_stand", "moving carry untouched")
	driver.queue_free()
	await process_frame
	print("SOURCE_READY_FIRE ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
