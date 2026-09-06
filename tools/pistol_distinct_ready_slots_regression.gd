extends SceneTree

const WeaponProfile := preload("res://scripts/weapons/weapon_animation_profile.gd")
const Ownership := preload("res://scripts/player/weapon_ownership_contract.gd")
const STANDING_READY := &"slot_probe_pistol_ready_standing"
const CROUCHED_READY := &"slot_probe_pistol_ready_crouched"
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_check_profile_defaults()
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(60)
	var player := scene.get_node("Player") as CharacterBody3D
	var controller := scene.get_node("WeaponController")
	var mannequin := player.get_node("Mannequin")
	var driver := mannequin.get("production_animation") as Node
	player.set_physics_process(false)
	mannequin.set_process(false)
	_expect(bool(controller.call("apply_authorized_weapon_pickup", "res://config/weapons/mark_23.json")), "canonical Mark 23 handoff")
	await _frames(24)
	var original: Dictionary = driver.get("equipped_weapon_handling_profile")
	var profile := original.duplicate(true)
	var slots: Dictionary = profile["animation_slots"]
	# This fixture proves absent-override fallback routing. Explicit Mark23 moving
	# sources are covered separately by pistol_compressed_movement_source_regression.
	for slot in ["idle_standing_moving", "ready_standing_moving", "ready_crouched_moving"]:
		slots.erase(slot)
	slots["idle_standing"] = "pistol_idle"
	slots["idle_crouched"] = "pistol_idle_kneeling"
	slots.erase("ready_standing")
	driver.set("equipped_weapon_handling_profile", profile)
	driver.call("_build_animation_tree")
	_expect_node(driver, &"modern_aim_idle", &"pistol_idle", "absent standing ready preserves existing idle-as-ready")
	_expect(StringName(driver.call("_standing_ready_frame_pose_clip")) == &"pistol_idle", "saved-frame sampler shares absent-slot fallback")
	# Distinct names alias existing imported clips in this process only. The test
	# proves routing without saving a candidate asset or changing weapon profiles.
	_add_clip_alias(driver, STANDING_READY, &"pistol_idle")
	_add_clip_alias(driver, CROUCHED_READY, &"pistol_idle_kneeling")
	slots["ready_standing"] = String(STANDING_READY)
	slots["ready_crouched"] = String(CROUCHED_READY)
	driver.set("equipped_weapon_handling_profile", profile)
	driver.call("_build_animation_tree")
	_expect_node(driver, &"standing_idle_base", &"pistol_idle", "standing base keeps low/idle slot")
	_expect_node(driver, &"modern_idle_crouch", &"pistol_idle_kneeling", "crouched base keeps idle slot")
	for node_name in [&"modern_aim_idle", &"standing_upper_aim_idle", &"standing_aim_frame_source", &"standing_idle_aim_frame_source"]:
		_expect_node(driver, node_name, STANDING_READY, "standing ready source %s" % node_name)
	for node_name in [&"crouch_upper_aim_idle", &"crouch_aim_frame_source", &"crouch_idle_aim_idle", &"crouch_idle_aim_frame_source"]:
		_expect_node(driver, node_name, CROUCHED_READY, "crouched ready source %s" % node_name)
	_expect(StringName(driver.call("_standing_ready_frame_pose_clip")) == STANDING_READY, "saved-frame sampler consumes explicit standing ready")
	for posture_index in [0, 1]:
		await _check_accepted_shot_cycle(player, controller, driver, posture_index)
	slots["ready_standing"] = "missing_ready_clip"
	driver.set("equipped_weapon_handling_profile", profile)
	driver.call("_build_animation_tree")
	_expect_node(driver, &"modern_aim_idle", &"pistol_idle", "unavailable optional ready falls back to idle")
	_expect(StringName(driver.call("_standing_ready_frame_pose_clip")) == &"pistol_idle", "sampler shares unavailable-slot fallback")
	scene.queue_free()
	await process_frame
	await _check_ready_previews()
	if failures.is_empty():
		print("PISTOL_DISTINCT_READY_SLOTS_REGRESSION PASS")
		quit(0)
	else:
		print("PISTOL_DISTINCT_READY_SLOTS_REGRESSION FAIL %s" % [failures])
		quit(1)

func _check_profile_defaults() -> void:
	for family in WeaponProfile.FAMILIES:
		var normalized := WeaponProfile.normalized_profile(family)
		var slots: Dictionary = normalized["animation_slots"]
		_expect(slots["ready_standing"] == slots["idle_standing"], "%s optional standing ready defaults to prior idle" % family)
		var crouch_default := "pistol_idle_kneeling" if family in ["ONE_HAND", "TWO_HAND_PISTOL"] else "aim_idle_crouch"
		_expect(slots["ready_crouched"] == crouch_default, "%s preserves established crouched ready fallback" % family)
	var custom := WeaponProfile.normalized_profile("TWO_HAND_PISTOL", {"animation_slots": {"idle_standing": "custom_low_idle"}})
	_expect(custom["animation_slots"]["ready_standing"] == "custom_low_idle", "old weapon-specific idle override remains ready fallback")
	for slot in ["ready_standing", "ready_crouched"]:
		_expect(slot in WeaponProfile.SLOT_ORDER and WeaponProfile.SLOT_LABELS.has(slot), "%s is editable through generated Gunsmith selectors" % slot)
		var policy := Ownership.preview_policy(slot, &"custom_forward_pose")
		_expect(StringName(policy.get("resolved_owner", &"")) == Ownership.READY_SOLVER, "%s preview owner follows slot rather than arbitrary clip name" % slot)
		var mobility_policy := Ownership.preview_policy(slot, &"jump shooting")
		_expect(StringName(mobility_policy.get("resolved_owner", &"")) == Ownership.MOBILITY_CHEST_CARRY, "%s preserves the existing full-body mobility safety priority" % slot)

func _check_ready_previews() -> void:
	var lab := (load("res://gun_calibration_lab.tscn") as PackedScene).instantiate()
	root.add_child(lab)
	await _frames(24)
	var animation_player := lab.get("animation_player") as AnimationPlayer
	var library := animation_player.get_animation_library(&"")
	var clip_name := &"slot_probe_forward_pose"
	var clip := Animation.new()
	clip.length = 0.1
	clip.loop_mode = Animation.LOOP_LINEAR
	library.add_animation(clip_name, clip)
	for slot in ["ready_standing", "ready_crouched", "idle_standing"]:
		lab.call("_preview_animation_slot", slot, clip_name)
		await _frames(24)
		_expect(animation_player.current_animation == clip_name, "%s preview persists beyond its clip length" % slot)
		if slot.begins_with("ready_"):
			_expect(StringName(lab.get("weapon_owner_state")) == Ownership.READY_SOLVER and not bool(lab.get("is_reloading")), "%s uses the shared ready owner in the running Gunsmith scene" % slot)
	lab.call("_preview_animation_slot", "fire_standing", clip_name)
	await _frames(24)
	_expect(animation_player.current_animation != clip_name and animation_player.current_animation == StringName(lab.call("_posture_idle_clip")), "transient fire preview still returns to existing posture idle")
	lab.queue_free()
	await process_frame

func _add_clip_alias(driver: Node, alias: StringName, source: StringName) -> void:
	var player := driver.get("animation_player") as AnimationPlayer
	var library := driver.get("dynamic_anim_lib") as AnimationLibrary
	library.add_animation(alias, player.get_animation(source).duplicate(true))
	var clips: Dictionary = driver.get("available_clips")
	clips[alias] = true
	var paths: Dictionary = driver.get("clip_paths")
	paths[alias] = paths.get(source, "")

func _check_accepted_shot_cycle(player: CharacterBody3D, controller: Node, driver: Node, posture_index: int) -> void:
	var posture := &"STANDING" if posture_index == 0 else &"CROUCHED"
	var idle := &"pistol_idle" if posture_index == 0 else &"pistol_idle_kneeling"
	var ready := STANDING_READY if posture_index == 0 else CROUCHED_READY
	driver.call("clear_fire_ready_aim")
	player.call("_try_set_posture", posture_index)
	driver.call("set_visual_inputs", Vector2.ZERO, posture, 0.0, 0.0, 0.0, false, 0.0)
	await _frames(36)
	_expect(StringName(driver.call("_select_visual_clip")) == idle, "%s starts in its idle slot without permanent ready" % posture)
	var graph := driver.get("locomotion_graph") as RefCounted
	var fire_count := int(graph.get("fire_trigger_count"))
	var shot: Dictionary = controller.call("request_fire")
	_expect(bool(shot.get("fired", false)), "%s accepts canonical shot" % posture)
	await _frames(8)
	_expect(StringName(driver.call("_select_visual_clip")) == ready and StringName(driver.get("current_clip")) == ready, "%s selects distinct ready on accepted shot" % posture)
	var debug: Dictionary = driver.call("get_animation_debug_state")
	var latch: Dictionary = debug.get("fire_upper_body_latch", {})
	_expect(String(latch.get("owner_state", "")) == "FIRE_RECOVERY" and float(latch.get("grace_remaining_seconds", 0.0)) > 1.0 and float(latch.get("grace_remaining_seconds", 9.0)) <= 1.2, "%s retains the existing 1.2 second recovery owner" % posture)
	_expect(int(graph.get("fire_trigger_count")) == fire_count and StringName(graph.get("active_fire_clip")) == &"", "%s never launches a fire OneShot" % posture)
	var recovered := false
	for _frame in range(900):
		await _frames(1)
		if float(driver.get("weapon_ready_weight")) <= 0.0:
			recovered = true
			break
	await _frames(2)
	_expect(recovered and StringName(driver.call("_select_visual_clip")) == idle and StringName(driver.get("current_clip")) == idle, "%s returns to distinct idle after existing recovery fade" % posture)

func _expect_node(driver: Node, node_name: StringName, expected: StringName, label: String) -> void:
	var tree := driver.get("animation_tree") as AnimationTree
	var graph := tree.tree_root as AnimationNodeBlendTree
	var node := graph.get_node(node_name) as AnimationNodeAnimation
	_expect(node != null and node.animation == expected, label)

func _frames(count: int) -> void:
	for _frame in count:
		await process_frame
		await physics_frame

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PISTOL_READY_SLOTS_CHECK PASS %s" % label)
	else:
		failures.append(label)
		push_error("PISTOL_READY_SLOTS_CHECK FAIL %s" % label)
