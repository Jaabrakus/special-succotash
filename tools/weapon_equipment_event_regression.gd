extends SceneTree

const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const WeaponAnimationProfile := preload(
	"res://scripts/weapons/weapon_animation_profile.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "playable scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _frames(50)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var controller := scene.get_node_or_null("WeaponController")
	var mannequin := player.get_node_or_null("Mannequin") if player != null else null
	var driver = mannequin.get("production_animation") if mannequin != null else null
	_expect(
		controller != null and driver != null,
		"playable weapon and animation consumers are ready"
	)
	if controller == null or driver == null:
		scene.queue_free()
		_finish()
		return
	var skeleton := driver.get("skeleton") as Skeleton3D
	_expect(
		skeleton != null
		and skeleton.find_children(
			"CombatReadySpineCCDIK3D", "CCDIK3D", true, false
		).size() == 1,
		"operator starts with one combat-ready spine modifier"
	)
	var pickup_path := "res://config/weapons/m4a1.json"
	var pickup_config := WeaponContract.load_config(pickup_path)
	var pickup_handling: Dictionary = pickup_config.get("handling_profile", {})
	_expect(
		String(pickup_handling.get("family", ""))
			== WeaponAnimationProfile.FAMILY_TWO_HAND_RIFLE,
		"rifle pickup resolves to the two-hand rifle family"
	)
	_expect(
		bool(pickup_handling.get("standing_fire_uses_aim_idle", false))
		and bool(pickup_handling.get("crouched_fire_uses_aim_idle", false)),
		"two-hand rifle family supplies stable standing/crouched fire recovery"
	)
	var previous_weapon = driver.get("weapon_node")
	var previous_instance_id: int = (
		previous_weapon.get_instance_id() if previous_weapon != null else 0
	)
	_expect(
		bool(controller.call("apply_authorized_weapon_pickup", pickup_path)),
		"an authorized pickup applies through the canonical equipment handoff"
	)
	await _frames(12)
	var equipped_weapon = driver.get("weapon_node")
	_expect(
		equipped_weapon != null
		and equipped_weapon.get_instance_id() != previous_instance_id
		and String(equipped_weapon.get_meta("weapon_id", ""))
			== String(pickup_config.get("weapon_id", "")),
		"pickup replaces the rendered rifle and retains its weapon identity"
	)
	var equip_debug: Dictionary = driver.call("get_animation_debug_state")
	var equip_event: Dictionary = equip_debug.get("last_event_presentation", {})
	_expect(
		String(equip_event.get("event", "")) == "WEAPON_EQUIPPED"
		and String(equip_event.get("weapon_family", ""))
			== WeaponAnimationProfile.FAMILY_TWO_HAND_RIFLE
		and "APPLY_WEAPON_FAMILY" in (equip_event.get("effects", []) as Array),
		"WEAPON_EQUIPPED selects the persistent rifle animation family"
	)
	_expect(
		driver.find_children("OperatorAnimationTree", "AnimationTree", false, false).size() == 1,
		"equipment handoff leaves exactly one live animation graph"
	)
	var fire_trigger_count_before := int(equip_debug.get("fire_trigger_count", 0))
	var shot: Dictionary = controller.call("request_fire")
	_expect(bool(shot.get("fired", false)), "the equipped rifle can fire")
	await _frames(2)
	var fire_debug: Dictionary = driver.call("get_animation_debug_state")
	var fire_event: Dictionary = fire_debug.get("last_event_presentation", {})
	_expect(
		String(fire_event.get("event", "")) == "FIRE_ACCEPTED"
		and String(fire_event.get("weapon_family", ""))
			== WeaponAnimationProfile.FAMILY_TWO_HAND_RIFLE
		and not String(fire_event.get("state", "")).is_empty(),
		"FIRE_ACCEPTED resolves inside the family selected by the pickup"
	)
	var fire_latch: Dictionary = fire_debug.get("fire_upper_body_latch", {})
	_expect(
		String(fire_latch.get("owner_state", "")) == "FIRE_RECOVERY"
		and bool(fire_debug.get("presentation_fire_selected", false))
		and int(fire_debug.get("fire_trigger_count", 0)) == fire_trigger_count_before
		and String(fire_debug.get("active_fire_clip", "")).is_empty(),
		"M4 accepted shot selects FIRE_RECOVERY without the old fire one-shot"
	)
	var solver = driver.get("weapon_pose_solver")
	var solver_debug: Dictionary = solver.call("get_debug_state") if solver != null else {}
	_expect(
		bool(solver_debug.get("socket_contract_active", false)),
		"hand IK and weapon sockets rebind to the replacement rifle"
	)
	var comparison_paths := [
		"res://config/weapons/m4a1.json",
		"res://config/weapons/ak-47.json",
	]
	for swap_index in range(10):
		var comparison_path: String = comparison_paths[
			swap_index % comparison_paths.size()
		]
		_expect(
			bool(controller.call(
				"apply_authorized_weapon_pickup",
				comparison_path
			)),
			"AK/M4 comparison weapon swap %d succeeds" % (swap_index + 1)
		)
		await _frames(1)
		var comparison_config := WeaponContract.load_config(comparison_path)
		var comparison_handling: Dictionary = comparison_config.get(
			"handling_profile",
			{}
		)
		_expect(
			bool(comparison_handling.get("standing_fire_uses_aim_idle", false))
			and bool(comparison_handling.get("crouched_fire_uses_aim_idle", false)),
			"AK/M4 swap %d inherits stable standing/crouched recovery"
				% (swap_index + 1)
		)
		var comparison_weapon = driver.get("weapon_node")
		_expect(
			comparison_weapon != null
			and String(comparison_weapon.get_meta("weapon_id", ""))
				== String(comparison_config.get("weapon_id", ""))
			and String(
				(driver.get("equipped_weapon_config") as Dictionary).get(
					"model_fbx",
					""
				)
			) == String(comparison_config.get("model_fbx", "")),
			"AK/M4 swap %d reaches the exact canonical model contract"
				% (swap_index + 1)
		)
	_expect(
		skeleton != null
		and skeleton.find_children(
			"CombatReadySpineCCDIK3D", "CCDIK3D", true, false
		).size() == 1,
		"repeated weapon swaps reuse one combat-ready spine modifier"
	)
	scene.queue_free()
	await process_frame
	await process_frame
	_finish()


func _frames(count: int) -> void:
	for _frame in count:
		await process_frame
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("WEAPON_EQUIPMENT_EVENT_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("WEAPON_EQUIPMENT_EVENT_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("WEAPON_EQUIPMENT_EVENT_REGRESSION PASS")
		quit(0)
	else:
		print("WEAPON_EQUIPMENT_EVENT_REGRESSION FAIL ", failures)
		quit(1)
