extends SceneTree

const WEAPON_DIRECTORY := "res://config/weapons"
const NON_WEAPON_DOCUMENTS := {
	"operator_loadout.json": true,
	"recom_weapons_catalog.json": true,
}
const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const WeaponAnimationProfile := preload(
	"res://scripts/weapons/weapon_animation_profile.gd"
)
const OperatorAnimationProfile := preload(
	"res://scripts/player/operator_animation_profile.gd"
)

var failures: Array[String] = []
var weapon_paths: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_collect_weapon_paths()
	_expect(weapon_paths.size() >= 40, "canonical firearm catalog is fully discovered")
	_check_saved_family_contracts()
	await _check_live_equipment_chain(0, &"STANDING")
	await _check_live_equipment_chain(1, &"CROUCHED")
	_finish()


func _collect_weapon_paths() -> void:
	for file_name in DirAccess.get_files_at(WEAPON_DIRECTORY):
		if (
			not file_name.ends_with(".json")
			or NON_WEAPON_DOCUMENTS.has(file_name)
		):
			continue
		var path := "%s/%s" % [WEAPON_DIRECTORY, file_name]
		var config := WeaponContract.load_config(path)
		if String(config.get("weapon_id", "")).is_empty():
			continue
		weapon_paths.append(path)
	weapon_paths.sort()


func _check_saved_family_contracts() -> void:
	var profile := OperatorAnimationProfile.new()
	profile.load_project_map()
	for path in weapon_paths:
		var config := WeaponContract.load_config(path)
		var weapon_id := String(config.get("weapon_id", path.get_file().get_basename()))
		var handling: Dictionary = config.get("handling_profile", {})
		var family := String(handling.get("family", ""))
		_expect(
			family in WeaponAnimationProfile.FAMILIES,
			"%s resolves to a declared animation family" % weapon_id
		)
		_expect(
			bool(handling.get("standing_fire_uses_aim_idle", false))
			and bool(handling.get("crouched_fire_uses_aim_idle", false)),
			"%s inherits stable standing/crouched FIRE_RECOVERY" % weapon_id
		)
		var standing_state := profile.resolve_animation_event(
			&"FIRE_ACCEPTED", &"STANDING", StringName(family)
		)
		var crouched_state := profile.resolve_animation_event(
			&"FIRE_ACCEPTED", &"CROUCHED", StringName(family)
		)
		_expect(
			"reload" not in String(standing_state).to_lower()
			and "reload" not in String(crouched_state).to_lower(),
			"%s FIRE_ACCEPTED cannot resolve to reload" % weapon_id
		)


func _check_live_equipment_chain(posture_index: int, posture_name: StringName) -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "%s canonical playable scene loads" % posture_name)
	if packed == null:
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _frames(50)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var controller := scene.get_node_or_null("WeaponController")
	var mannequin := player.get_node_or_null("Mannequin") if player != null else null
	var driver = mannequin.get("production_animation") if mannequin != null else null
	_expect(
		player != null and controller != null and driver != null,
		"%s canonical weapon and animation consumers are ready" % posture_name
	)
	if player == null or controller == null or driver == null:
		scene.queue_free()
		return
	_expect(
		bool(player.call("_try_set_posture", posture_index)),
		"canonical player enters %s" % posture_name
	)
	await _frames(8)
	var operator_profile := OperatorAnimationProfile.new()
	operator_profile.load_project_map()
	for path in weapon_paths:
		var config := WeaponContract.load_config(path)
		var weapon_id := String(config.get("weapon_id", path.get_file().get_basename()))
		var family := StringName(
			(config.get("handling_profile", {}) as Dictionary).get("family", "")
		)
		var equipped := bool(controller.call("apply_authorized_weapon_pickup", path))
		_expect(
			equipped,
			"%s equips through the canonical %s handoff" % [weapon_id, posture_name]
		)
		if not equipped:
			continue
		await _await_ballistics_ready(controller, weapon_id, posture_name)
		var before: Dictionary = driver.call("get_animation_debug_state")
		var trigger_count_before := int(before.get("fire_trigger_count", 0))
		var shot: Dictionary = controller.call("request_fire")
		var shot_accepted := bool(shot.get("fired", false))
		var shot_label := "%s accepts a canonical %s shot" % [
			weapon_id, posture_name
		]
		if not shot_accepted:
			shot_label += " (%s)" % JSON.stringify(shot)
		_expect(shot_accepted, shot_label)
		if not bool(shot.get("fired", false)):
			continue
		await _frames(2)
		var after: Dictionary = driver.call("get_animation_debug_state")
		var latch: Dictionary = after.get("fire_upper_body_latch", {})
		var event: Dictionary = after.get("last_event_presentation", {})
		var expected_state := operator_profile.resolve_animation_event(
			&"FIRE_ACCEPTED", posture_name, family
		)
		_expect(
			String(latch.get("owner_state", "")) == "FIRE_RECOVERY"
			and is_equal_approx(
				float(latch.get("grace_duration_seconds", 0.0)), 1.2
			)
			and float(latch.get("grace_remaining_seconds", 0.0)) > 1.0
			and bool(after.get("presentation_fire_selected", false))
			and int(after.get("fire_trigger_count", 0)) == trigger_count_before
			and String(after.get("active_fire_clip", "")).is_empty()
			and String(event.get("event", "")) == "FIRE_ACCEPTED"
			and StringName(event.get("weapon_family", "")) == family
			and StringName(event.get("state", "")) == expected_state,
			"%s %s shot uses %s recovery without a fire OneShot"
			% [weapon_id, posture_name, expected_state]
		)
		driver.call("clear_fire_ready_aim")
		await _frames(1)
	scene.queue_free()
	await process_frame
	await process_frame


func _await_ballistics_ready(
	controller: Node,
	weapon_id: String,
	posture_name: StringName
) -> void:
	var ballistics = controller.get("ballistics")
	_expect(
		ballistics != null,
		"%s %s cadence owner exists" % [weapon_id, posture_name]
	)
	if ballistics == null:
		return
	# The cooldown belongs to the shared server weapon and legitimately survives
	# an equipment swap. Wait for that owner instead of mutating its state.
	for _frame in 240:
		if float(ballistics.get("fire_cooldown")) <= 0.0:
			return
		await process_frame
		await physics_frame
	_expect(
		false,
		"%s %s cadence owner becomes ready" % [weapon_id, posture_name]
	)


func _frames(count: int) -> void:
	for _frame in count:
		await process_frame
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("ALL_WEAPON_FIRE_RECOVERY_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("ALL_WEAPON_FIRE_RECOVERY_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("ALL_WEAPON_FIRE_RECOVERY_REGRESSION PASS weapons=%d" % weapon_paths.size())
		quit(0)
		return
	print("ALL_WEAPON_FIRE_RECOVERY_REGRESSION FAIL ", failures)
	quit(1)
