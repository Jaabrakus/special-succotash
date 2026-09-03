extends SceneTree

## Exercises the canonical main/equip/fire/presentation chain for every saved
## pistol, assault-rifle, and SMG profile. This is diagnostics only: it reads
## the live pose owner after an accepted shot and never writes runtime tuning.

const WEAPON_DIRECTORY := "res://config/weapons"
const INCLUDED_CATEGORIES := {
	"Pistols": true,
	"Assault Rifles": true,
	"Submachine Guns": true,
}
const EXCLUDED_WEAPON_IDS := {
	"designator": true,
	"air_to_ground_missile": true,
	"exploding_fuel": true,
}
const MAX_HAND_CONTACT_ERROR_M := 0.01
const MAX_BORE_AIM_ERROR_DEG := 1.0
const MAX_PISTOL_AXIAL_ROLL_DEG := 12.0
const FIRE_RECOVERY_SECONDS := 1.2
const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const WeaponAnimationProfile := preload(
	"res://scripts/weapons/weapon_animation_profile.gd"
)
const OperatorAnimationProfile := preload(
	"res://scripts/player/operator_animation_profile.gd"
)

var failures: Array[String] = []
var weapon_paths: Array[String] = []
var checked_cases: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_collect_weapon_paths()
	_expect(
		weapon_paths.size() >= 30,
		"all saved pistol, assault-rifle, and SMG profiles are discovered"
	)
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "canonical res://main.tscn loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _frames(60)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var controller := scene.get_node_or_null("WeaponController")
	var mannequin := player.get_node_or_null("Mannequin") if player != null else null
	var driver = mannequin.get("production_animation") if mannequin != null else null
	_expect(
		player != null and controller != null and driver != null,
		"canonical player, weapon controller, and presentation consumer are ready"
	)
	if player != null and controller != null and driver != null:
		# Keep the canonical driver processing, but stop the mannequin's ordinary
		# gameplay input forwarder from replacing this proof's explicit Ready Aim
		# value with the live player's current zero-input value each frame.
		player.set_physics_process(false)
		mannequin.set_process(false)
		var animation_profile := OperatorAnimationProfile.new()
		animation_profile.load_project_map()
		for posture_case in [
			{"index": 0, "name": &"STANDING", "aim_height_m": 1.48},
			{"index": 1, "name": &"CROUCHED", "aim_height_m": 1.20},
		]:
			var posture_name := StringName(posture_case["name"])
			_expect(
				bool(player.call("_try_set_posture", int(posture_case["index"]))),
				"canonical player enters %s" % posture_name
			)
			await _frames(12)
			for path in weapon_paths:
				await _check_live_case(
					path,
					posture_name,
					float(posture_case["aim_height_m"]),
					player,
					controller,
					driver,
					animation_profile
				)
	_expect(
		checked_cases == weapon_paths.size() * 2,
		"every discovered firearm is checked standing and crouched"
	)
	scene.queue_free()
	await process_frame
	await process_frame
	_finish()


func _collect_weapon_paths() -> void:
	for file_name in DirAccess.get_files_at(WEAPON_DIRECTORY):
		if not file_name.ends_with(".json"):
			continue
		var path := "%s/%s" % [WEAPON_DIRECTORY, file_name]
		var raw := _read_dictionary(path)
		if (
			raw.is_empty()
			or not INCLUDED_CATEGORIES.has(String(raw.get("category", "")))
		):
			continue
		var weapon_id := String(raw.get("weapon_id", file_name.get_basename()))
		if EXCLUDED_WEAPON_IDS.has(weapon_id):
			continue
		weapon_paths.append(path)
	weapon_paths.sort()


func _check_live_case(
	path: String,
	posture_name: StringName,
	aim_height_m: float,
	player: CharacterBody3D,
	controller: Node,
	driver,
	animation_profile
) -> void:
	checked_cases += 1
	var raw := _read_dictionary(path)
	var config := WeaponContract.load_config(path)
	var weapon_id := String(raw.get("weapon_id", path.get_file().get_basename()))
	var label := "%s %s" % [weapon_id, posture_name]
	var expected_family := _expected_family(raw)
	var actual_family := StringName(
		(config.get("handling_profile", {}) as Dictionary).get("family", "")
	)
	_expect(
		actual_family == expected_family,
		"%s resolves to independently expected family %s"
		% [label, expected_family]
	)
	var equipped := bool(controller.call("apply_authorized_weapon_pickup", path))
	_expect(equipped, "%s equips through the canonical authorized handoff" % label)
	if not equipped:
		return
	var aim_target := (
		player.global_position
		+ Vector3.UP * aim_height_m
		+ Vector3.FORWARD * 25.0
	)
	driver.call(
		"set_visual_inputs",
		Vector2.ZERO,
		posture_name,
		0.0,
		0.0,
		1.0,
		false,
		0.0,
		0.0,
		&"LOCOMOTION",
		0.0,
		&"WALK",
		0.0,
		aim_target,
		Vector2.ZERO,
		0.0,
		&"IDLE",
		0.0
	)
	await _frames(20)
	_expect(
		String(controller.get("equipped_weapon_id")) == weapon_id
		and StringName(driver.get("equipped_weapon_family")) == expected_family,
		"%s reaches canonical gameplay and animation-family consumers" % label
	)
	var ready_state: Dictionary = driver.call("get_animation_debug_state")
	var ready_latch: Dictionary = ready_state.get("fire_upper_body_latch", {})
	var ready_pose: Dictionary = ready_state.get("weapon_pose", {})
	_expect(
		StringName(ready_latch.get("owner_state", &"")) == &"BASE"
		and not bool(ready_state.get("presentation_fire_selected", true))
		and float(ready_state.get("clean_ready_pose_weight", 0.0)) >= 0.98,
		"%s ordinary Ready Aim uses the clean recovery-quality upper-body pose"
		% label
	)
	_expect_ready_ownership_and_contact(
		driver,
		ready_pose,
		label,
		"ordinary Ready Aim",
		expected_family == WeaponAnimationProfile.FAMILY_TWO_HAND_PISTOL
	)
	await _await_ballistics_ready(controller, label)
	var before: Dictionary = driver.call("get_animation_debug_state")
	var before_latch: Dictionary = before.get("fire_upper_body_latch", {})
	var fire_trigger_count_before := int(before.get("fire_trigger_count", 0))
	var accepted_shot_count_before := int(
		before_latch.get("accepted_shot_count", 0)
	)
	var shot: Dictionary = controller.call("request_fire")
	var shot_accepted := bool(shot.get("fired", false))
	var shot_label := "%s accepts a canonical shot" % label
	if not shot_accepted:
		shot_label += " (%s)" % JSON.stringify(shot)
	_expect(shot_accepted, shot_label)
	if not shot_accepted:
		return
	await _frames(18)
	var state: Dictionary = driver.call("get_animation_debug_state")
	var latch: Dictionary = state.get("fire_upper_body_latch", {})
	var event: Dictionary = state.get("last_event_presentation", {})
	var pose: Dictionary = state.get("weapon_pose", {})
	var expected_state: StringName = StringName(
		animation_profile.resolve_animation_event(
			&"FIRE_ACCEPTED", posture_name, expected_family
		)
	)
	_expect(
		StringName(latch.get("owner_state", &"")) == &"FIRE_RECOVERY"
		and bool(latch.get("selected", false))
		and is_equal_approx(
			float(latch.get("grace_duration_seconds", 0.0)),
			FIRE_RECOVERY_SECONDS
		)
		and float(latch.get("grace_remaining_seconds", 0.0)) > 0.0
		and int(latch.get("accepted_shot_count", 0))
			== accepted_shot_count_before + 1
		and bool(state.get("presentation_fire_selected", false))
		and int(state.get("fire_trigger_count", -1))
			== fire_trigger_count_before
		and StringName(state.get("active_fire_clip", &"invalid")) == &""
		and StringName(event.get("event", &"")) == &"FIRE_ACCEPTED"
		and StringName(event.get("weapon_family", &"")) == expected_family
		and StringName(event.get("state", &"")) == expected_state,
		"%s uses the posture-matched 1.2-second recovery without a fire OneShot"
		% label
	)
	_expect_ready_ownership_and_contact(
		driver,
		pose,
		label,
		"FIRE_RECOVERY",
		expected_family == WeaponAnimationProfile.FAMILY_TWO_HAND_PISTOL
	)
	driver.call("clear_fire_ready_aim")
	await _frames(2)


func _expect_ready_ownership_and_contact(
	driver: Node,
	pose: Dictionary,
	label: String,
	state_label: String,
	is_pistol: bool
) -> void:
	_expect(
		bool(pose.get("socket_contract_active", false))
		and bool(pose.get("right_hand_owns_ready_weapon", false))
		and not bool(pose.get("weapon_solver_owned", true))
		and StringName(pose.get("weapon_owner", &"")) == &"READY_SOLVER"
		and bool(pose.get("support_hand_socket_ik_enabled", false))
		and not bool(pose.get("hand_socket_ik_enabled", true))
		and bool(pose.get("support_hand_grip_locked", false)),
		"%s %s keeps one right-hand weapon owner and support-hand-only IK"
		% [label, state_label]
	)
	var trigger_error_m := float(pose.get("trigger_hand_error_m", INF))
	var support_error_m := float(pose.get("support_hand_error_m", INF))
	var aim_error_deg := float(pose.get("weapon_aim_error_deg", INF))
	_expect(
		is_finite(trigger_error_m)
		and trigger_error_m <= MAX_HAND_CONTACT_ERROR_M,
		"%s %s trigger-hand contact %.5f m is at or below %.2f m"
		% [label, state_label, trigger_error_m, MAX_HAND_CONTACT_ERROR_M]
	)
	_expect(
		is_finite(support_error_m)
		and support_error_m <= MAX_HAND_CONTACT_ERROR_M,
		"%s %s support-hand contact %.5f m is at or below %.2f m"
		% [label, state_label, support_error_m, MAX_HAND_CONTACT_ERROR_M]
	)
	_expect(
		is_finite(aim_error_deg)
		and aim_error_deg <= MAX_BORE_AIM_ERROR_DEG,
		"%s %s bore/aim error %.5f degrees is at or below %.1f degree"
		% [label, state_label, aim_error_deg, MAX_BORE_AIM_ERROR_DEG]
	)
	if is_pistol:
		var axial_roll_deg := _pistol_axial_roll_degrees(driver)
		_expect(
			is_finite(axial_roll_deg)
			and absf(axial_roll_deg) <= MAX_PISTOL_AXIAL_ROLL_DEG,
			"%s %s pistol optic-up roll %+.3f degrees is within %.1f degrees"
			% [label, state_label, axial_roll_deg, MAX_PISTOL_AXIAL_ROLL_DEG]
		)


func _pistol_axial_roll_degrees(driver: Node) -> float:
	var solver = driver.get("weapon_pose_solver")
	var skeleton := driver.get("skeleton") as Skeleton3D
	if solver == null or skeleton == null:
		return INF
	var muzzle := solver.get("muzzle_socket") as Marker3D
	var barrel_base := solver.get("barrel_base_socket") as Marker3D
	var optic := solver.get("optic_socket") as Marker3D
	if muzzle == null or barrel_base == null or optic == null:
		return INF
	var bore := muzzle.global_position - barrel_base.global_position
	if bore.length_squared() < 0.000001:
		return INF
	bore = bore.normalized()
	var actual_up := optic.global_position - barrel_base.global_position
	actual_up -= bore * actual_up.dot(bore)
	var expected_up := skeleton.global_basis.y.normalized()
	expected_up -= bore * expected_up.dot(bore)
	if (
		actual_up.length_squared() < 0.000001
		or expected_up.length_squared() < 0.000001
	):
		return INF
	actual_up = actual_up.normalized()
	expected_up = expected_up.normalized()
	return rad_to_deg(atan2(
		bore.dot(expected_up.cross(actual_up)),
		expected_up.dot(actual_up)
	))


func _expected_family(raw: Dictionary) -> StringName:
	if String(raw.get("category", "")) == "Pistols":
		return WeaponAnimationProfile.FAMILY_TWO_HAND_PISTOL
	var searchable := " ".join([
		String(raw.get("weapon_id", "")),
		String(raw.get("display_name", "")),
		String(raw.get("model_fbx", "")),
	]).to_lower()
	if "shotgun" in searchable or "sniper" in searchable:
		return WeaponAnimationProfile.FAMILY_LONG_GUN
	return WeaponAnimationProfile.FAMILY_TWO_HAND_RIFLE


func _await_ballistics_ready(controller: Node, label: String) -> void:
	var ballistics = controller.get("ballistics")
	_expect(ballistics != null, "%s cadence owner exists" % label)
	if ballistics == null:
		return
	for _frame in 240:
		if float(ballistics.get("fire_cooldown")) <= 0.0:
			return
		await process_frame
		await physics_frame
	_expect(false, "%s cadence owner becomes ready" % label)


func _frames(count: int) -> void:
	for _frame in count:
		await process_frame
		await physics_frame


func _read_dictionary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var value: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("FIREARM_FAMILY_LIVE_CONTACT_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("FIREARM_FAMILY_LIVE_CONTACT_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print(
			"FIREARM_FAMILY_LIVE_CONTACT_REGRESSION PASS weapons=%d cases=%d"
			% [weapon_paths.size(), checked_cases]
		)
		quit(0)
		return
	print("FIREARM_FAMILY_LIVE_CONTACT_REGRESSION FAIL ", failures)
	quit(1)
