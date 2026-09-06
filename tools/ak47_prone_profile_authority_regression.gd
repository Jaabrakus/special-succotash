extends SceneTree

## Canonical proof that the AK-47's saved support-only contact contract remains
## authoritative in prone. Prone may select firing presentation, but it must not
## silently upgrade this profile to the full two-arm ready solver.

const Ownership := preload("res://scripts/player/weapon_ownership_contract.gd")
const CONFIG_PATH := "res://config/weapons/ak-47.json"
const FIRE_SAMPLE_FRAMES: Array[int] = [1, 4, 12]

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config := _read_dictionary(CONFIG_PATH)
	var handling_profile: Dictionary = config.get("handling_profile", {})
	var dynamic_hold: Dictionary = handling_profile.get("dynamic_hold", {})
	_expect(
		not bool(dynamic_hold.get("hand_socket_ik_enabled", true))
		and bool(dynamic_hold.get("support_hand_socket_ik_enabled", false))
		and bool(dynamic_hold.get("right_hand_owns_weapon", false)),
		"saved AK-47 profile keeps authored trigger arm plus support-only IK"
	)
	_expect(
		Ownership.resolve(&"PRONE", &"", 0.0, false)
		== Ownership.RELAXED_RIFLE_LOCOMOTION,
		"relaxed prone does not force READY_SOLVER ownership"
	)

	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "canonical res://main.tscn loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate() as Node3D
	root.add_child(scene)
	await _frames(60)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var controller := scene.get_node_or_null("WeaponController")
	var mannequin := player.get_node_or_null("Mannequin") if player != null else null
	var driver = mannequin.get("production_animation") if mannequin != null else null
	_expect(
		player != null and controller != null and mannequin != null and driver != null,
		"canonical movement, weapon, mannequin, and presentation owners are live"
	)
	if player == null or controller == null or mannequin == null or driver == null:
		scene.queue_free()
		_finish()
		return
	_expect(
		bool(controller.call("apply_authorized_weapon_pickup", CONFIG_PATH)),
		"AK-47 equips through the canonical authorized handoff"
	)
	await _frames(24)
	_expect(bool(player.call("_try_set_posture", 2)), "canonical player enters prone")
	await _frames(72)
	var relaxed_debug: Dictionary = driver.call("get_animation_debug_state")
	var relaxed_pose: Dictionary = relaxed_debug.get("weapon_pose", {})
	_print_pose("RELAXED", relaxed_pose)
	_expect(
		StringName(relaxed_pose.get("weapon_owner", &""))
		== Ownership.RELAXED_RIFLE_LOCOMOTION,
		"live relaxed prone keeps authored-rifle ownership"
	)
	_expect(
		_profile_is_support_only(relaxed_pose)
		and StringName(relaxed_pose.get("support_hand_mode", &""))
		== Ownership.SUPPORT_IK_TO_WEAPON,
		"live relaxed prone consumes the saved support-only profile"
	)
	_expect(
		not bool(relaxed_pose.get("right_hand_ik_running", true))
		and bool(relaxed_pose.get("weapon_parent_is_animation_mount", false)),
		"live relaxed prone leaves the trigger arm authored and weapon on its hand mount"
	)

	await _await_ballistics_ready(controller)
	var shot: Dictionary = controller.call("request_fire")
	_expect(bool(shot.get("fired", false)), "prone AK-47 shot is accepted")
	if bool(shot.get("fired", false)):
		var previous_sample_frame := 0
		for sample_frame in FIRE_SAMPLE_FRAMES:
			await _frames(sample_frame - previous_sample_frame)
			previous_sample_frame = sample_frame
			var fire_debug: Dictionary = driver.call("get_animation_debug_state")
			var fire_pose: Dictionary = fire_debug.get("weapon_pose", {})
			_print_pose("FIRE_FRAME_%d" % sample_frame, fire_pose)
			_expect(
				_profile_is_support_only(fire_pose)
				and not bool(fire_pose.get("right_hand_ik_running", true))
				and bool(fire_pose.get("weapon_parent_is_animation_mount", false)),
				"prone fire frame %d cannot upgrade AK-47 to full-arm IK"
				% sample_frame
			)

	scene.queue_free()
	await process_frame
	_finish()


func _profile_is_support_only(pose: Dictionary) -> bool:
	return (
		not bool(pose.get("hand_socket_ik_enabled", true))
		and bool(pose.get("support_hand_socket_ik_enabled", false))
	)


func _print_pose(label: String, pose: Dictionary) -> void:
	print(
		(
			"AK47_PRONE_PROFILE_METRIC phase=%s owner=%s hand_socket_ik=%s "
			+ "support_socket_ik=%s right_hand_ik=%s animation_mount=%s support_mode=%s"
		) % [
			label,
			str(pose.get("weapon_owner", &"")),
			str(pose.get("hand_socket_ik_enabled", true)),
			str(pose.get("support_hand_socket_ik_enabled", false)),
			str(pose.get("right_hand_ik_running", true)),
			str(pose.get("weapon_parent_is_animation_mount", false)),
			str(pose.get("support_hand_mode", &"")),
		]
	)


func _await_ballistics_ready(controller: Node) -> void:
	var ballistics = controller.get("ballistics")
	if ballistics == null:
		return
	for _frame in 240:
		if float(ballistics.get("fire_cooldown")) <= 0.0:
			return
		await process_frame
		await physics_frame


func _read_dictionary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed as Dictionary if parsed is Dictionary else {}


func _frames(count: int) -> void:
	for _frame in count:
		await process_frame
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("AK47_PRONE_PROFILE_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("AK47_PRONE_PROFILE_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("AK47_PRONE_PROFILE_AUTHORITY_REGRESSION PASS")
		quit(0)
		return
	print("AK47_PRONE_PROFILE_AUTHORITY_REGRESSION FAIL %s" % [failures])
	quit(1)
