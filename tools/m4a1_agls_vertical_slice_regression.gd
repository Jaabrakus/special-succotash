extends SceneTree

const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const AssetRegistry := preload("res://scripts/weapons/agls_weapon_asset_registry.gd")
const VisualRigResolver := preload(
	"res://scripts/labs/gunsmith2/weapon_visual_rig_resolver.gd"
)
const VisualRigContract := preload(
	"res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd"
)
const GunsmithCatalog := preload(
	"res://scripts/labs/gunsmith/gunsmith_recom_catalog_adapter.gd"
)

const PROFILE_PATH := "res://config/weapons/m4a1.json"
const VISUAL_RIG_PATH := "res://config/weapon_visual_rigs/m4a1_agls_v10.json"
const PRE_ISO_RELOAD_VISUAL_RIG_PATH := "res://config/weapon_visual_rigs/m4a1_agls_v9.json"
const PRE_POCKET_VISUAL_RIG_PATH := "res://config/weapon_visual_rigs/m4a1_agls_v8.json"
const PRE_CHEST_FRAME_VISUAL_RIG_PATH := "res://config/weapon_visual_rigs/m4a1_agls_v7.json"
const PRE_RELEASE_VISUAL_RIG_PATH := "res://config/weapon_visual_rigs/m4a1_agls_v6.json"
const PRE_LATERAL_VISUAL_RIG_PATH := "res://config/weapon_visual_rigs/m4a1_agls_v5.json"
const STOCK_VISUAL_RIG_PATH := "res://config/weapon_visual_rigs/m4a1_agls_v4.json"
const CARRY_ONLY_VISUAL_RIG_PATH := "res://config/weapon_visual_rigs/m4a1_agls_v2.json"
const PREVIOUS_VISUAL_RIG_PATH := "res://config/weapon_visual_rigs/m4a1_agls_v1.json"
const MODEL_PATH := "res://assets/external/agls_intake/imported/weapons/m4a1/m4a1.scn"
const EXPECTED_SLOTS := {
	"fire_crouched": "crouch_fire",
	"fire_prone": "prone_fire",
	"fire_standing": "combat_fire",
	"idle_crouched": "idle_crouch",
	"idle_prone": "idle_prone",
	"idle_standing": "aim_idle",
	"ready_crouched": "aim_idle_crouch",
	"reload_crouched": "iso_rifle_reload_crouched",
	"reload_prone": "iso_rifle_reload_prone",
	"reload_standing": "iso_rifle_reload_standing",
}
const RUNTIME_SOCKET_NAMES := [
	"Socket_RightHand",
	"Socket_LeftHand",
	"Socket_Muzzle",
	"Socket_BarrelBase",
	"Socket_Buttstock",
	"Socket_Optic",
	"Socket_Ejection",
]

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var raw_profile := _read_json(PROFILE_PATH)
	var profile := WeaponContract.load_config(PROFILE_PATH)
	var visual_document := _read_json(VISUAL_RIG_PATH)
	VisualRigResolver.clear_cache()
	var resolved := VisualRigResolver.resolve_for_presentation(profile)

	_check_saved_contract(raw_profile, profile, visual_document, resolved)
	_validate_exported_weapon_bones()
	await _check_live_equipment()
	_finish()


func _check_saved_contract(
	raw_profile: Dictionary,
	profile: Dictionary,
	visual_document: Dictionary,
	resolved: Dictionary
) -> void:
	_expect(not raw_profile.is_empty(), "M4A1 profile is valid JSON")
	_expect(not profile.is_empty(), "M4A1 canonical config normalizes")
	_expect(
		String(profile.get("visual_rig_id", "")) == "m4a1_agls_v10",
		"M4A1 references its published AGLS visual rig"
	)
	var validation := VisualRigContract.validate(visual_document, true)
	_expect(bool(validation.get("ok", false)), "M4A1 visual rig passes its contract")
	_expect(
		String(resolved.get("_visual_rig_id", "")) == "m4a1_agls_v10",
		"presentation resolver applies the assigned M4A1 visual rig"
	)

	var visual: Dictionary = visual_document.get("visual", {})
	var stock_visual: Dictionary = _read_json(STOCK_VISUAL_RIG_PATH).get("visual", {})
	_expect(not stock_visual.is_empty(), "immutable M4A1 v4 stock-contact rig is retained")
	var carry_visual := visual.duplicate(true)
	var prior_visual: Dictionary = _read_json(PRE_ISO_RELOAD_VISUAL_RIG_PATH).get("visual", {})
	for slot in ["reload_standing", "reload_crouched", "reload_prone"]:
		carry_visual.handling_profile.animation_slots[slot] = prior_visual.handling_profile.animation_slots[slot]
	_expect(carry_visual == prior_visual, "M4A1 v10 changes only three reload slots versus immutable v9")
	var released_dynamic: Dictionary = carry_visual.get("handling_profile", {}).get("dynamic_hold", {})
	_expect(released_dynamic.get("ready_shoulder_pocket", {}) == {"downward_m": 0.065, "right_wrist_roll_degrees": -15.0}, "M4A1 v9 publishes the measured non-right shoulder pocket and wrist calibration")
	released_dynamic.erase("ready_shoulder_pocket")
	_expect(carry_visual == _read_json(PRE_POCKET_VISUAL_RIG_PATH).get("visual", {}), "M4A1 v9 changes only the ready shoulder pocket versus immutable v8")
	_expect(bool(released_dynamic.get("standing_idle_square_pelvis", false)), "M4A1 v7 opts into forward standing-idle pelvis")
	var released_strafe: Dictionary = released_dynamic.get("strafe_carry", {})
	_expect(String(released_strafe.get("right_stock_release_frame", "")) == "chest_forward", "M4A1 v8 releases forward from the turned chest, not along the barrel")
	_expect(is_equal_approx(float(released_strafe.get("right_stock_release_m", 0.0)), 0.33), "M4A1 v8 provides measured front-torso reach clearance")
	released_strafe.erase("right_stock_release_frame")
	var pre_chest_visual: Dictionary = _read_json(PRE_CHEST_FRAME_VISUAL_RIG_PATH).get("visual", {})
	released_strafe["right_stock_release_m"] = pre_chest_visual.get("handling_profile", {}).get("dynamic_hold", {}).get("strafe_carry", {}).get("right_stock_release_m", 0.0)
	_expect(carry_visual == pre_chest_visual, "M4A1 v8 changes only right release frame and clearance versus immutable v7")
	_expect(float(released_strafe.get("right_stock_release_m", 0.0)) > 0.0, "M4A1 v7 releases the stock on right strafe")
	released_dynamic.erase("standing_idle_square_pelvis")
	released_strafe.erase("right_stock_release_m")
	_expect(carry_visual == _read_json(PRE_RELEASE_VISUAL_RIG_PATH).get("visual", {}), "M4A1 v7 changes only idle pelvis and right stock release versus immutable v6")
	var carry_handling: Dictionary = carry_visual.get("handling_profile", {})
	_expect(carry_handling.get("locomotion_slots", {}) == {"run_left": "run_lateral_left", "run_right": "run_lateral_right", "crouch_left": "crouch_lateral_left", "crouch_right": "crouch_lateral_right"}, "M4A1 v6 selects only the four scoped full-lateral leg routes")
	carry_handling.erase("locomotion_slots")
	_expect(carry_visual == _read_json(PRE_LATERAL_VISUAL_RIG_PATH).get("visual", {}), "M4A1 v6 changes only lateral leg slots versus immutable v5")
	var visual_without_full_turn := carry_visual.duplicate(true)
	var stock_strafe: Dictionary = stock_visual.get("handling_profile", {}).get("dynamic_hold", {}).get("strafe_carry", {})
	var full_turn_strafe: Dictionary = visual_without_full_turn.get("handling_profile", {}).get("dynamic_hold", {}).get("strafe_carry", {})
	_expect(is_equal_approx(float(stock_strafe.get("right_hip_follow_weight", -1.0)), 0.12), "immutable M4A1 v4 retains its original partial-turn setting")
	_expect(is_equal_approx(float(full_turn_strafe.get("right_hip_follow_weight", -1.0)), 1.0), "M4A1 v6 opts into full rightward body turn")
	full_turn_strafe["right_hip_follow_weight"] = stock_strafe.get("right_hip_follow_weight", -1.0)
	_expect(visual_without_full_turn == stock_visual, "M4A1 carry fields change only rightward hip follow versus immutable v4")
	var previous_document := _read_json(PREVIOUS_VISUAL_RIG_PATH)
	_expect(not previous_document.is_empty(), "previous immutable M4A1 rig remains available")
	_expect(not _read_json(CARRY_ONLY_VISUAL_RIG_PATH).is_empty(), "intermediate immutable M4A1 carry rig remains available")
	var visual_without_carry := carry_visual.duplicate(true)
	var new_dynamic: Dictionary = (visual_without_carry.get("handling_profile", {}) as Dictionary).get("dynamic_hold", {})
	_expect(
		is_equal_approx(float(new_dynamic.get("locomotion_ready_carry_weight", 0.0)), 1.0),
		"published M4A1 v6 includes the carry opt-in"
	)
	_expect(
		new_dynamic.get("strafe_carry", {}) == {"right_hip_follow_weight": 1.0, "left_elbow_flare_degrees": 12.0},
		"published M4A1 v6 includes full rightward turn and unchanged leftward elbow flare"
	)
	new_dynamic.erase("locomotion_ready_carry_weight")
	new_dynamic.erase("strafe_carry")
	_expect(bool(new_dynamic.get("authored_shoulder_stock_enabled", false)), "M4A1 v6 preserves scoped authored stock contact")
	new_dynamic.erase("authored_shoulder_stock_enabled")
	# The repository extractor omits this optional value when the canonical
	# profile relies on its documented 1.0 default. Compare its resolved value.
	_expect(is_equal_approx(float(visual_without_carry.get("user_scale_multiplier", 1.0)), 1.0), "M4A1 v6 preserves unit user scale")
	visual_without_carry["user_scale_multiplier"] = float(visual_without_carry.get("user_scale_multiplier", 1.0))
	_expect(
		visual_without_carry == previous_document.get("visual", {}),
		"M4A1 visual changes only lateral slots, carry, asymmetric strafe and stock fields versus original v1"
	)
	for field_name in VisualRigContract.VISUAL_FIELDS:
		if not raw_profile.has(field_name):
			continue
		_expect(
			visual.has(field_name),
			"published M4A1 rig includes canonical visual field %s" % field_name
		)
		if visual.has(field_name):
			_expect(
				visual[field_name] == raw_profile[field_name],
				"published and canonical M4A1 %s agree" % field_name
			)
		_expect(
			resolved.get(field_name) == raw_profile[field_name],
			"resolver preserves accepted M4A1 %s" % field_name
		)

	_expect(String(resolved.get("model_fbx", "")) == MODEL_PATH, "runtime uses the AGLS M4A1")
	_expect(AssetRegistry.preferred_model_path(profile) == MODEL_PATH, "asset registry selects the M4A1")
	var gunsmith := GunsmithCatalog.resolve("m4a1")
	_expect(String(gunsmith.get("model_fbx", "")) == MODEL_PATH, "Gunsmith opens the AGLS M4A1")

	var sockets: Dictionary = resolved.get("weapon_sockets", {})
	_expect(
		sockets.size() == VisualRigContract.REQUIRED_SOCKETS.size(),
		"M4A1 publishes exactly the seven canonical sockets"
	)
	for socket_name in VisualRigContract.REQUIRED_SOCKETS:
		_expect(sockets.has(socket_name), "M4A1 has %s" % socket_name)
	var muzzle := WeaponContract.vector3_from_map(sockets.get("muzzle_socket", {}), Vector3.ZERO)
	var barrel := WeaponContract.vector3_from_map(sockets.get("barrel_base_socket", {}), Vector3.ZERO)
	_expect(muzzle.distance_to(barrel) > 0.15, "M4A1 bore markers define a usable barrel")

	var handling: Dictionary = resolved.get("handling_profile", {})
	var slots: Dictionary = handling.get("animation_slots", {})
	_expect(slots == EXPECTED_SLOTS, "M4A1 uses the shared accepted aim, fire, and reload slots")
	var obsolete_weapon_specific_route := false
	for clip_value in slots.values():
		obsolete_weapon_specific_route = (
			obsolete_weapon_specific_route
			or String(clip_value).ends_with("_m4a1")
		)
	_expect(
		not obsolete_weapon_specific_route,
		"M4A1 visual rig cannot restore obsolete weapon-specific pose routes"
	)
	var ready_aim: Dictionary = handling.get("ready_aim", {})
	_expect(
		is_equal_approx(float(ready_aim.get("fire_hold_seconds", 0.0)), 1.2),
		"M4A1 fire recovery remains 1.2 seconds"
	)

	var dynamic_hold: Dictionary = handling.get("dynamic_hold", {})
	_expect(
		is_equal_approx(float(dynamic_hold.get("locomotion_ready_carry_weight", 0.0)), 1.0),
		"resolver preserves published M4A1 carry opt-in"
	)
	_expect(
		bool(dynamic_hold.get("animation_drives_ready_hands", false)),
		"shared authored animation drives the ready hands"
	)
	_expect(
		not bool(dynamic_hold.get("authored_animation_owns_weapon_mount", true)),
		"right-hand attachment remains the weapon mount owner"
	)
	_expect(
		not bool(dynamic_hold.get("hand_socket_ik_enabled", true))
		and bool(dynamic_hold.get("support_hand_socket_ik_enabled", false))
		and bool(dynamic_hold.get("right_hand_owns_weapon", false)),
		"M4A1 uses support-hand-only socket IK around the right-hand weapon owner"
	)
	_expect(
		is_equal_approx(float(dynamic_hold.get("support_hand_ik_blend_seconds", 0.0)), 0.2),
		"M4A1 support hand uses the accepted 0.2 second blend"
	)
	_expect(
		not bool(dynamic_hold.get("fire_saved_joint_rotations_enabled", true))
		and not bool(dynamic_hold.get("fire_spine_ccdik_enabled", true)),
		"M4A1 fire cannot restore saved-joint or spine-CCDIK distortion"
	)
	for obsolete_key in [
		"native_presentation_enabled",
		"native_support_hand_ik_enabled",
		"native_support_hand_weight",
		"procedural_ready_hand_weight",
		"procedural_ready_spine_weight",
	]:
		_expect(
			not dynamic_hold.has(obsolete_key),
			"M4A1 published rig omits obsolete %s" % obsolete_key
		)

	var mount: Dictionary = resolved.get("operator_mount", {})
	_expect(
		String(mount.get("attachment_mode", "")) == "trigger_hand_socket"
		and String(mount.get("bone_name", "")) == "mixamorig_RightHand",
		"M4A1 stays attached to the canonical trigger hand"
	)
	_expect(
		WeaponContract.vector3_from_map(mount.get("position", {}), Vector3.ONE).is_zero_approx(),
		"M4A1 has no guessed operator hand offset"
	)
	_expect(
		profile.get("ballistics", {}) == resolved.get("ballistics", {}),
		"visual rig does not change M4A1 ballistics"
	)
	_expect(
		profile.get("fire_modes", []) == resolved.get("fire_modes", []),
		"visual rig does not change M4A1 fire modes"
	)


func _check_live_equipment() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "canonical playable scene loads")
	if packed == null:
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _frames(50)
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	var controller := scene.get_node_or_null("WeaponController")
	var camera_rig := scene.get_node_or_null("IndependentCameraRig")
	var mannequin := player.get_node_or_null("Mannequin") if player != null else null
	var driver = mannequin.get("production_animation") if mannequin != null else null
	_expect(
		controller != null and driver != null and camera_rig != null,
		"canonical weapon and operator presentation consumers are ready"
	)
	if controller == null or driver == null or camera_rig == null:
		scene.queue_free()
		return

	_expect(
		bool(controller.call("apply_authorized_weapon_pickup", PROFILE_PATH)),
		"canonical authorized equipment handoff accepts M4A1 without loadout dependence"
	)
	var previous_rig_probe := "--previous-rig-probe" in OS.get_cmdline_user_args()
	if previous_rig_probe:
		# Diagnostic negative control only. Read the immutable previous rig into
		# this process's existing presentation owner; never save or modify profiles.
		var old_config := WeaponContract.load_config(PROFILE_PATH).duplicate(true)
		old_config["visual_rig_id"] = "m4a1_agls_v1"
		var old_visual: Dictionary = _read_json(PREVIOUS_VISUAL_RIG_PATH).get("visual", {})
		for field in old_visual:
			old_config[field] = old_visual[field]
		_expect(bool(driver.call("notify_weapon_equipped", old_config)), "previous M4A1 rig diagnostic handoff")
	await _frames(12)
	var weapon := driver.get("weapon_node") as Node3D
	var live_config: Dictionary = driver.get("equipped_weapon_config")
	var live_handling: Dictionary = driver.get("equipped_weapon_handling_profile")
	print("M4A1_AGLS_LIVE_ROUTES previous_rig=", previous_rig_probe, " ", JSON.stringify(live_handling.get("animation_slots", {})))
	_expect(
		weapon != null and String(weapon.get_meta("weapon_id", "")) == "m4a1",
		"canonical runtime renders the equipped M4A1 identity"
	)
	_expect(
		String(live_config.get("model_fbx", "")) == MODEL_PATH,
		"canonical equipment consumer receives the exact AGLS M4A1 model"
	)
	# Normalization supplies the standing ready fallback at the canonical
	# presentation boundary. Keep the raw published-route check above exact.
	var expected_live_slots := EXPECTED_SLOTS.duplicate(true)
	expected_live_slots["ready_standing"] = "aim_idle"
	_expect(
		(live_handling.get("animation_slots", {}) as Dictionary) == expected_live_slots,
		"canonical equipment consumer receives the shared M4A1 action routes"
	)
	var live_dynamic: Dictionary = live_handling.get("dynamic_hold", {})
	_expect(
		is_equal_approx(float(live_dynamic.get("locomotion_ready_carry_weight", 0.0)), 0.0 if previous_rig_probe else 1.0),
		"canonical equipment consumer receives published M4A1 carry opt-in"
	)
	_expect(
		not bool(live_dynamic.get("hand_socket_ik_enabled", true))
		and bool(live_dynamic.get("support_hand_socket_ik_enabled", false)),
		"canonical equipment consumer receives support-hand-only IK"
	)
	for socket_name in RUNTIME_SOCKET_NAMES:
		_expect(
			weapon != null and weapon.find_child(socket_name, true, false) is Marker3D,
			"canonical equipped M4A1 builds %s" % socket_name
		)

	var shot: Dictionary = controller.call("request_fire")
	_expect(bool(shot.get("fired", false)), "canonical equipped M4A1 can fire")
	await _frames(2)
	var recovery_remaining := float(driver.get("_fire_ready_hold_remaining"))
	_expect(
		recovery_remaining > 1.0 and recovery_remaining <= 1.2,
		"canonical M4A1 enters the 1.2 second fire-recovery window"
	)
	await _frames(18)
	var muzzle_position: Vector3 = mannequin.call("get_active_muzzle_position")
	var barrel_direction: Vector3 = mannequin.call("get_active_barrel_direction")
	var reticle_direction := muzzle_position.direction_to(
		Vector3(camera_rig.get("weapon_aim_point"))
	)
	var bore_error_deg := rad_to_deg(barrel_direction.angle_to(reticle_direction))
	print("M4A1_AGLS_METRIC live_bore_to_reticle_error_deg=%.4f" % bore_error_deg)
	_expect(
		bore_error_deg <= 6.0,
		"canonical M4A1 physical bore faces the reticle during fire recovery"
	)
	var pose_debug: Dictionary = driver.call("get_animation_debug_state").get(
		"weapon_pose",
		{}
	)
	_expect(
		float(pose_debug.get("support_hand_error_m", 1.0)) <= 0.03,
		"canonical M4A1 support palm remains on the authored foregrip"
	)
	scene.queue_free()
	await process_frame
	await process_frame


func _validate_exported_weapon_bones() -> void:
	var packed := load(MODEL_PATH) as PackedScene
	_expect(packed != null, "AGLS M4A1 scene is loadable")
	if packed == null:
		return
	var instance := packed.instantiate()
	var skeleton := _find_skeleton(instance)
	_expect(skeleton != null, "AGLS M4A1 contains its weapon skeleton")
	if skeleton != null:
		for bone_name in ["trigger", "muzzle", "barrel", "stock", "sights"]:
			_expect(skeleton.find_bone(bone_name) >= 0, "AGLS export preserves %s" % bone_name)
	instance.free()


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed as Dictionary if parsed is Dictionary else {}


func _frames(count: int) -> void:
	for _frame in count:
		await process_frame
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("M4A1_AGLS_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("M4A1_AGLS_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("M4A1_AGLS_VERTICAL_SLICE_REGRESSION PASS")
		quit(0)
	else:
		print("M4A1_AGLS_VERTICAL_SLICE_REGRESSION FAIL ", failures)
		quit(1)
