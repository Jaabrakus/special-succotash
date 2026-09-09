extends SceneTree

const Profile = preload("res://scripts/player/operator_animation_profile.gd")
const Driver = preload("res://scripts/player/operator_animation_driver.gd")
const Weapons = preload("res://scripts/weapons/weapon_rig_contract.gd")
var failures: Array[String] = []

func _initialize() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	_run.call_deferred()

func _run() -> void:
	var p := Profile.new()
	p.load_project_map()
	check(bool(p.locomotion.get("legacy_pistol_upper_body", false)), "main profile activates hybrid")
	check(bool(p.locomotion.get("preserve_source_locomotion", false)), "main profile preserves SEAL gait")
	var driver := Driver.new()
	root.add_child(driver)
	await process_frame
	var count := 0
	for file in DirAccess.get_files_at("res://config/weapons"):
		if not file.ends_with(".json"):
			continue
		var config: Dictionary = Weapons.load_config("res://config/weapons/" + file)
		if config.get("handling_profile", {}).get("family", "") != "TWO_HAND_PISTOL":
			continue
		count += 1
		check(driver.notify_weapon_equipped(config), file + " equips")
		var tree: AnimationNodeBlendTree = driver.animation_tree.tree_root
		check(tree.has_node(&"legacy_pistol_upper"), file + " has upper layer")
		var upper: AnimationNodeBlend2 = tree.get_node(&"legacy_pistol_upper")
		check(upper.filter_enabled and upper.is_path_filtered(NodePath(".:mixamorig_RightHand")), "hands selected")
		check(not upper.is_path_filtered(NodePath(".:mixamorig_Hips")) and not upper.is_path_filtered(NodePath(".:mixamorig_LeftUpLeg")), "hips and legs never borrowed")
		for stance in ["standing", "crouched"]:
			var clip := StringName("legacy_pistol_ready_" + stance)
			check(driver._equipped_action_clip("ready_" + stance, &"aim_idle") == clip, file + " pistol-specific aim")
			check(driver.animation_player.get_animation(clip).loop_mode == Animation.LOOP_LINEAR, "legacy pose loops")
		check(p.family_animation_slots.TWO_HAND_PISTOL["locomotion/run_left"] != p.family_animation_slots.TWO_HAND_PISTOL["locomotion/run_right"], "distinct native left/right takes")
	check(count >= 9, "all nine catalog pistols tested")
	check(driver.notify_weapon_equipped(Weapons.load_config("res://config/weapons/ak-47.json")), "rifle re-equip")
	check(not driver.animation_tree.tree_root.has_node(&"legacy_pistol_upper"), "rifle removes pistol layer")
	driver.queue_free()
	await process_frame
	print("PISTOL_HYBRID_MAIN ", "PASS" if failures.is_empty() else "FAIL", " pistols=", count, " ", failures)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
