extends SceneTree

## Resolve through the actual driver API and compare with the graph consumer.
## Fixtures replace only in-memory saved contracts; no pose or gameplay runs.
const ActionDriver := preload("res://scripts/player/operator_animation_driver_actions.gd")
const Profile := preload("res://scripts/player/operator_animation_profile.gd")
const Graph := preload("res://scripts/player/operator_locomotion_blend_tree.gd")
const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const POSTURES: Array[StringName] = [&"STANDING", &"CROUCHED", &"PRONE"]

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var driver := ActionDriver.new()
	var profile := Profile.new()
	var graph := Graph.new()
	driver.animation_profile = profile
	graph.profile = profile
	profile.load_project_map()
	profile.family_animation_slots = {"TWO_HAND_PISTOL": {}}
	driver.available_clips = profile.clip_paths.duplicate()
	# Resolving a replacement stance pose must never restart the active reload.
	driver.requested_action = &"fixture_active_reload"
	driver.requested_action_remaining = 0.73
	driver.requested_action_total_duration = 1.91
	driver.requested_action_playback_speed = 0.84

	for stance in POSTURES:
		var suffix := String(stance).to_lower()
		for action in [&"fire", &"reload"]:
			var slot := "%s_%s" % [action, suffix]
			var family_clip := StringName("fixture_pistol_" + slot)
			profile.family_animation_slots.TWO_HAND_PISTOL[slot] = String(family_clip)
			driver.available_clips[family_clip] = true

	# Real saved rifles retain all six weapon-specific reload selections even
	# when a complete pistol family override is available at the same time.
	for weapon_id in ["m4a1", "ak-47"]:
		_equip_contract(driver, graph, WeaponContract.load_config("res://config/weapons/%s.json" % weapon_id))
		for stance in POSTURES:
			driver.posture = stance
			var slot := "reload_" + String(stance).to_lower()
			var expected := StringName(driver.equipped_weapon_handling_profile.animation_slots[slot])
			_expect(expected != &"" and driver.available_clips.has(expected), weapon_id + " saved reload is available")
			_expect_routes(driver, graph, &"reload", expected, weapon_id + " " + String(stance))

	_equip_contract(driver, graph, WeaponContract.load_config("res://config/weapons/mark_23.json"))
	_expect(driver.equipped_weapon_family == &"TWO_HAND_PISTOL", "Mark 23 uses its normalized pistol family")
	# Empty weapon slots were the failing condition: family lookup must still run.
	driver.equipped_weapon_handling_profile["animation_slots"] = {}
	graph.weapon_handling_profile = driver.equipped_weapon_handling_profile
	for stance in POSTURES:
		driver.posture = stance
		for action in [&"fire", &"reload"]:
			var slot := "%s_%s" % [action, String(stance).to_lower()]
			var family_clip := StringName("fixture_pistol_" + slot)
			_expect_routes(driver, graph, action, family_clip, "empty weapon slots " + slot)
			var weapon_clip := StringName("fixture_weapon_" + slot)
			driver.available_clips[weapon_clip] = true
			driver.equipped_weapon_handling_profile.animation_slots[slot] = String(weapon_clip)
			_expect_routes(driver, graph, action, family_clip, "family precedes weapon " + slot)
			# A missing source asset must preserve this weapon's own take, even
			# when a rifle family defines the identical action slot.
			profile.family_animation_slots.TWO_HAND_PISTOL[slot] = "missing_source_asset"
			profile.family_animation_slots["TWO_HAND_RIFLE"] = {slot: "rifle_only_override"}
			driver.available_clips[&"rifle_only_override"] = true
			_expect_routes(driver, graph, action, weapon_clip, "unavailable family " + slot)
			profile.family_animation_slots.TWO_HAND_PISTOL.erase(slot)
			_expect_routes(driver, graph, action, weapon_clip, "sparse family " + slot)
			driver.equipped_weapon_handling_profile.animation_slots[slot] = "missing_weapon_asset"
			var fallback: StringName = profile.resolve_semantic_action(action, stance)
			_expect_routes(driver, graph, action, fallback, "both unavailable retain semantic fallback " + slot)

	profile.family_animation_slots["TWO_HAND_PISTOL"] = {"grenade_toss_standing": "rifle_only_override"}
	driver.posture = &"STANDING"
	_expect(driver.resolve_semantic_action(&"grenade_toss") == profile.resolve_semantic_action(&"grenade_toss", &"STANDING"), "unrelated semantic actions retain their existing route")
	_expect(driver.resolve_semantic_action(&"missing_action") == &"", "unknown actions remain unresolved")
	_expect(driver.requested_action == &"fixture_active_reload", "resolution preserves active action identity")
	_expect(is_equal_approx(driver.requested_action_remaining, 0.73), "resolution preserves remaining action time")
	_expect(is_equal_approx(driver.requested_action_total_duration, 1.91), "resolution preserves total action time")
	_expect(is_equal_approx(driver.requested_action_playback_speed, 0.84), "resolution preserves playback rate")
	driver.free()
	for failure in failures:
		push_error(failure)
	print("SOURCE_ACTION_ROUTING ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)


func _equip_contract(driver: Node3D, graph: RefCounted, config: Dictionary) -> void:
	driver.equipped_weapon_handling_profile = config.get("handling_profile", {}).duplicate(true)
	driver.equipped_weapon_family = StringName(driver.equipped_weapon_handling_profile.get("family", ""))
	graph.weapon_handling_profile = driver.equipped_weapon_handling_profile


func _expect_routes(driver: Node3D, graph: RefCounted, action: StringName, expected: StringName, label: String) -> void:
	var actual: StringName = driver.resolve_semantic_action(action)
	var slot := "%s_%s" % [action, String(driver.posture).to_lower()]
	var fallback: StringName = driver.animation_profile.resolve_semantic_action(action, driver.posture)
	_expect(actual == expected, label + " resolves expected clip")
	_expect(actual == driver._equipped_action_clip(slot, fallback), label + " agrees with pose consumer")
	_expect(actual == graph._weapon_action_clip(slot, fallback, driver.available_clips), label + " agrees with graph consumer")


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
