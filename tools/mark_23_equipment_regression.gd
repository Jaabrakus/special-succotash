extends SceneTree

const MARK_23_PATH := "res://config/weapons/mark_23.json"
const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const WeaponAnimationProfile := preload(
	"res://scripts/weapons/weapon_animation_profile.gd"
)
const OperatorAnimationProfile := preload(
	"res://scripts/player/operator_animation_profile.gd"
)
const WeaponPoseSolver := preload(
	"res://scripts/player/operator_weapon_pose_solver.gd"
)
const StockConstraint := preload(
	"res://scripts/player/operator_weapon_stock_constraint.gd"
)

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config := WeaponContract.load_config(MARK_23_PATH)
	_check_saved_contract(config)
	_check_family_routes()
	_check_solver_replacement(config)
	await _check_live_equipment(config)
	_finish()


func _check_saved_contract(config: Dictionary) -> void:
	_expect(not config.is_empty(), "Mark 23 canonical config loads")
	_expect(
		bool(config.get("socket_contract_authored", false)),
		"Mark 23 uses authored sockets instead of generated rifle contacts"
	)
	var handling: Dictionary = config.get("handling_profile", {})
	var slots: Dictionary = handling.get("animation_slots", {})
	_expect(
		String(handling.get("family", ""))
			== WeaponAnimationProfile.FAMILY_TWO_HAND_PISTOL,
		"Mark 23 resolves to TWO_HAND_PISTOL"
	)
	_expect(
		String(slots.get("idle_standing", "")) == "pistol_idle"
		and String(slots.get("idle_crouched", "")) == "pistol_idle_kneeling"
		and String(slots.get("ready_crouched", "")) == "pistol_idle_kneeling",
		"standing, crouched idle and moving crouch ready use pistol poses"
	)
	_expect(
		String(slots.get("fire_standing", "")) == "pistol_fire"
		and String(slots.get("fire_crouched", "")) == "pistol_fire",
		"legacy pistol recoil remains catalogued without owning accepted fire"
	)
	_expect(
		String(slots.get("reload_standing", "")).is_empty()
		and String(slots.get("reload_crouched", "")).is_empty()
		and String(slots.get("reload_prone", "")).is_empty(),
		"Mark 23 explicitly opts out of an unapproved weapon-specific reload take"
	)
	_expect(
		bool(handling.get("standing_fire_uses_aim_idle", false))
		and bool(handling.get("crouched_fire_uses_aim_idle", false)),
		"pistol family inherits stable standing and crouched fire recovery"
	)
	var model_size := _configured_model_size(config)
	_expect(
		model_size >= 0.20 and model_size <= 0.25,
		"configured Pistol_2 longest axis is human-scale (%.4f m)" % model_size
	)
	var sockets: Dictionary = config.get("weapon_sockets", {})
	var muzzle := _vector(sockets.get("muzzle_socket", {}))
	var barrel_base := _vector(sockets.get("barrel_base_socket", {}))
	var bore := muzzle - barrel_base
	_expect(
		bore.length() >= 0.15
		and bore.normalized().dot(Vector3.BACK) >= 0.999,
		"authored pistol bore is forward and independent of the rifle fallback"
	)
	_expect(
		_vector(sockets.get("left_hand_ik_target", {})).distance_to(
			_vector(sockets.get("right_hand_grip_target", {}))
		) <= 0.08,
		"two-hand pistol contacts remain together at the grip"
	)


func _check_family_routes() -> void:
	var profile := OperatorAnimationProfile.new()
	profile.load_project_map()
	_expect(
		profile.resolve_animation_event(
			&"FIRE_ACCEPTED", &"STANDING", &"TWO_HAND_PISTOL"
		) == &"pistol_idle",
		"standing FIRE_ACCEPTED resolves to the stable pistol ready pose"
	)
	_expect(
		profile.resolve_animation_event(
			&"FIRE_ACCEPTED", &"CROUCHED", &"TWO_HAND_PISTOL"
		) == &"pistol_idle_kneeling",
		"crouched FIRE_ACCEPTED resolves to the stable kneeling pistol pose"
	)
	_expect(
		profile.resolve_animation_event(
			&"WEAPON_EQUIPPED", &"STANDING", &"TWO_HAND_PISTOL"
		) == &"pistol_idle"
		and profile.resolve_animation_event(
			&"WEAPON_EQUIPPED", &"CROUCHED", &"TWO_HAND_PISTOL"
		) == &"pistol_idle_kneeling",
		"equipment event resets directly into the posture-matched pistol family"
	)
	_expect(
		profile.state_layer(&"pistol_fire") == "UPPER_BODY",
		"pistol recoil layers over standing or crouched locomotion"
	)


func _check_solver_replacement(config: Dictionary) -> void:
	var solver = WeaponPoseSolver.new()
	solver.configure_dynamic_hold({
		"animation_carry_weight": 0.1,
		"animation_carry_limit_m": 0.08,
		"reload_return_blend_seconds": 0.35,
		"hand_owned_aim_correction_limit_deg": 180.0,
		"right_hand_owns_weapon": false,
		"animation_drives_ready_hands": false,
		"hand_socket_ik_enabled": true,
		"support_hand_socket_ik_enabled": false,
		"support_hand_ik_blend_seconds": 0.75,
	})
	var mark_dynamic: Dictionary = (config.get("handling_profile", {}) as Dictionary).get(
		"dynamic_hold", {}
	)
	solver.configure_dynamic_hold(mark_dynamic)
	_expect(
		not bool(solver.hand_socket_ik_enabled)
		and bool(solver.support_hand_socket_ik_enabled)
		and bool(solver.right_hand_owns_ready_weapon),
		"Mark 23 replaces rifle solver ownership instead of inheriting it"
	)
	solver.configure_dynamic_hold({})
	_expect(
		is_equal_approx(float(solver.animation_carry_weight), 0.65)
		and is_equal_approx(float(solver.animation_carry_limit_m), 0.035)
		and bool(solver.hand_socket_ik_enabled)
		and not bool(solver.support_hand_socket_ik_enabled)
		and not bool(solver.right_hand_owns_ready_weapon),
		"an omitted next profile resets to component defaults without state leakage"
	)
	solver.free()

	var stock = StockConstraint.new()
	stock.configure({
		"enabled": true,
		"inward_offset_m": 0.14,
		"downward_offset_m": 0.14,
		"forward_offset_m": 0.14,
	})
	stock.configure({"enabled": false})
	_expect(
		not bool(stock.enabled)
		and is_equal_approx(float(stock.inward_offset_m), 0.055)
		and is_equal_approx(float(stock.downward_offset_m), 0.035)
		and is_equal_approx(float(stock.forward_offset_m), 0.015),
		"unstocked equipment clears inherited shoulder-pocket offsets"
	)
	stock.free()


func _check_live_equipment(config: Dictionary) -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "canonical playable scene loads")
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
		controller != null and driver != null,
		"canonical weapon and operator presentation consumers are ready"
	)
	if controller == null or driver == null:
		scene.queue_free()
		return

	# Seed the exact stale state that previously survived a rifle-to-pistol swap.
	driver.call("_trigger_fire_ready_aim")
	_expect(
		float(driver.get("_fire_ready_hold_remaining")) > 0.0,
		"precondition: rifle fire recovery is active before equipment swap"
	)
	_expect(
		bool(controller.call("apply_authorized_weapon_pickup", MARK_23_PATH)),
		"canonical authorized equipment handoff accepts the calibrated Mark 23"
	)
	await _frames(12)
	var weapon := driver.get("weapon_node") as Node3D
	var debug: Dictionary = driver.call("get_animation_debug_state")
	var equip_event: Dictionary = debug.get("last_event_presentation", {})
	var pose: Dictionary = debug.get("weapon_pose", {})
	_expect(
		String(driver.get("equipped_weapon_family")) == "TWO_HAND_PISTOL"
		and weapon != null
		and String(weapon.get_meta("weapon_id", "")) == "mark_23",
		"runtime tree and rendered weapon share Mark 23 pistol identity"
	)
	_expect(
		float(driver.get("_fire_ready_hold_remaining")) <= 0.001,
		"equipment swap clears the previous rifle fire-recovery latch"
	)
	_expect(
		String(equip_event.get("event", "")) == "WEAPON_EQUIPPED"
		and String(equip_event.get("weapon_family", "")) == "TWO_HAND_PISTOL"
		and String(equip_event.get("state", "")) == "pistol_idle",
		"live WEAPON_EQUIPPED resolves to pistol idle, not rifle aim"
	)
	_expect(
		not bool(pose.get("hand_socket_ik_enabled", true))
		and bool(pose.get("support_hand_socket_ik_enabled", false))
		and not bool((pose.get("buttstock_constraint", {}) as Dictionary).get("active", true)),
		"live Mark 23 uses support contact without a rifle stock solver"
	)
	_expect(
		weapon != null and _node_bounds_longest_axis(weapon) >= 0.20
		and _node_bounds_longest_axis(weapon) <= 0.25,
		"rendered Mark 23 remains within its saved 20-25 cm envelope"
	)
	_expect(
		driver.find_children("OperatorAnimationTree", "AnimationTree", false, false).size() == 1,
		"family swap leaves one rebuilt canonical AnimationTree"
	)

	var fire_trigger_count_before := int(debug.get("fire_trigger_count", 0))
	var shot: Dictionary = controller.call("request_fire")
	_expect(bool(shot.get("fired", false)), "equipped Mark 23 can fire authoritatively")
	await _frames(3)
	var fire_debug: Dictionary = driver.call("get_animation_debug_state")
	var fire_event: Dictionary = fire_debug.get("last_event_presentation", {})
	var fire_latch: Dictionary = fire_debug.get("fire_upper_body_latch", {})
	_expect(
		String(fire_event.get("event", "")) == "FIRE_ACCEPTED"
		and String(fire_event.get("weapon_family", "")) == "TWO_HAND_PISTOL"
		and String(fire_event.get("state", "")) == "pistol_idle",
		"accepted Mark 23 shot resolves to its family ready pose"
	)
	_expect(
		String(fire_latch.get("owner_state", "")) == "FIRE_RECOVERY"
		and bool(fire_debug.get("presentation_fire_selected", false))
		and int(fire_debug.get("fire_trigger_count", 0)) == fire_trigger_count_before
		and String(fire_debug.get("active_fire_clip", "")).is_empty(),
		"Mark 23 FIRE_RECOVERY bypasses the malformed pistol fire OneShot"
	)

	var reload_coordinator := scene.find_child(
		"WeaponReloadCoordinator", true, false
	)
	_expect(
		reload_coordinator != null,
		"canonical reload transaction owner is available"
	)
	if reload_coordinator != null:
		driver.call("clear_fire_ready_aim")
		var reload_before: Dictionary = driver.call("get_animation_debug_state")
		var reload_trigger_before := int(
			reload_before.get("standing_reload_trigger_count", 0)
		)
		_expect(
			bool(reload_coordinator.call("request_reload")),
			"Mark 23 reload starts only through the canonical reload transaction"
		)
		await _frames(3)
		var reload_debug: Dictionary = driver.call("get_animation_debug_state")
		var reload_event: Dictionary = reload_debug.get(
			"last_event_presentation", {}
		)
		print(
			(
				"MARK_23_RELOAD_METRIC family_route=%s selected=%s upper_body=%s standing_clip=%s "
				+ "standing_count=%d crouched_clip=%s crouched_count=%d "
				+ "available=%s player_has=%s slot=%s"
			) % [
				String(reload_event.get("family_route_state", "")),
				String(reload_event.get("state", "")),
				str(reload_debug.get("upper_body_reload_layer", false)),
				String(reload_debug.get("standing_reload_clip", "")),
				int(reload_debug.get("standing_reload_trigger_count", 0)),
				String(reload_debug.get("crouched_reload_clip", "")),
				int(reload_debug.get("crouched_reload_trigger_count", 0)),
				str((driver.get("available_clips") as Dictionary).has(&"pistol_reload")),
				str((driver.get("animation_player") as AnimationPlayer).has_animation(
					&"pistol_reload"
				)),
				String(
					(driver.get("equipped_weapon_handling_profile") as Dictionary)
					.get("animation_slots", {}).get("reload_standing", "")
				),
			]
		)
		_expect(
			String(reload_event.get("event", "")) == "RELOAD_STARTED"
			and String(reload_event.get("family_route_state", "")) == "pistol_reload"
			and String(reload_event.get("state", "")) == "reload"
			and bool(reload_debug.get("upper_body_reload_layer", false))
			and int(reload_debug.get("standing_reload_trigger_count", 0))
				== reload_trigger_before + 1
			and int(reload_debug.get("fire_trigger_count", 0))
				== fire_trigger_count_before
			and String(reload_debug.get("active_fire_clip", "")).is_empty(),
			"saved pistol reload opt-out stays reload-only without reviving fire"
		)
		_expect(
			bool(reload_coordinator.call("cancel_for_fire")),
			"canonical fire interrupt clears the pistol reload transaction"
		)
		await _frames(2)

	driver.set("movement_state", &"DIVING")
	await _frames(2)
	driver.set("movement_state", &"LOCOMOTION")
	await _frames(2)
	_expect(
		String(driver.get("equipped_weapon_family")) == "TWO_HAND_PISTOL"
		and String((driver.get("weapon_node") as Node3D).get_meta("weapon_id", "")) == "mark_23",
		"dive ownership returns to the same pistol family and weapon"
	)

	scene.queue_free()
	await process_frame
	await process_frame


func _configured_model_size(config: Dictionary) -> float:
	var scene := load(String(config.get("model_fbx", ""))) as PackedScene
	if scene == null:
		return 0.0
	var model := scene.instantiate() as Node3D
	var result := _node_bounds_longest_axis(model) * float(config.get("normalized_scale", 1.0))
	model.free()
	return result


func _node_bounds_longest_axis(node: Node3D) -> float:
	var bounds := AABB()
	var initialized := false
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var local_bounds := mesh_instance.mesh.get_aabb()
		var to_root := _transform_to_ancestor(node, mesh_instance)
		for x in [local_bounds.position.x, local_bounds.end.x]:
			for y in [local_bounds.position.y, local_bounds.end.y]:
				for z in [local_bounds.position.z, local_bounds.end.z]:
					var point := to_root * Vector3(x, y, z)
					if initialized:
						bounds = bounds.expand(point)
					else:
						bounds = AABB(point, Vector3.ZERO)
						initialized = true
	return maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)) if initialized else 0.0


func _transform_to_ancestor(ancestor: Node3D, node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != null and cursor != ancestor:
		result = (cursor as Node3D).transform * result
		cursor = cursor.get_parent()
	return result


func _vector(value: Variant) -> Vector3:
	var data: Dictionary = value if value is Dictionary else {}
	return Vector3(
		float(data.get("x", 0.0)),
		float(data.get("y", 0.0)),
		float(data.get("z", 0.0))
	)


func _frames(count: int) -> void:
	for _frame in count:
		await process_frame
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("MARK_23_EQUIPMENT_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("MARK_23_EQUIPMENT_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("MARK_23_EQUIPMENT_REGRESSION PASS")
		quit(0)
	else:
		print("MARK_23_EQUIPMENT_REGRESSION FAIL ", failures)
		quit(1)
