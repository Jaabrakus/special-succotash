extends "res://tools/rifle_reference_visual_probe.gd"

## Read-only canonical proof for docs/WEAPON_FAMILY_COMPLETION_TRANSLATION.md.
## --list-only | --weapons=m4a1,mark_23 | --capture
## --output-prefix=/private/tmp/firearm-family-transitions
## Omit --automated-test: that switch disables the actual movement input owner.
const Catalog := preload("res://scripts/weapons/socom_weapon_catalog.gd")
const Contract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const PistolDirectionProof := preload("res://tools/pistol_fire_direction_pose_regression.gd")
const EXPECTED_IDS := [
	"12_gauge_pump", "226", "552", "870", "9mm_pistol", "9mm_sub",
	"ak-47", "aks-74", "de__50", "f57", "f90", "hk5", "hk5sd", "m14",
	"m16a2", "m16a2-m203", "m3_12_gauge", "m40a1", "m4a1", "m4a1-m203",
	"m4a1_sd", "m60e3", "m63a", "m82a1a", "m87elr", "m9", "mark_23",
	"mark_23sd", "mark_46_mod_0", "model_18", "sr-25", "sr-25_sd", "ta_12_gauge",
]
const EXCLUDED_IDS := ["designator", "mk_3-a2", "air_to_ground_missile", "exploding_fuel"]
const FIREARM_CATEGORIES := ["Pistols", "Assault Rifles", "Submachine Guns", "Shotguns", "Sniper Rifles", "Machine Guns"]
const MAX_PALM_ERROR_M := 0.01
const MAX_AUTHORED_PALM_ERROR_M := 0.005
const MAX_BORE_ERROR_DEG := 1.0
const MAX_AUTHORED_BORE_ERROR_DEG := 0.5

var inventory: Array[Dictionary] = []
var selected_ids: Array[String] = []
var transition_rows: Array[Dictionary] = []
var list_only := false
var maximum_contacts: Dictionary = {}
var runtime_sources_at_start: Dictionary = {}
var first_fire_frame_pending := false
var physical_input_bindings: Dictionary = {}
var expected_accepted_shots := -1


func _initialize() -> void:
	output_prefix = "/private/tmp/firearm-family-transitions"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--weapons="):
			for value in argument.trim_prefix("--weapons=").split(",", false):
				selected_ids.append(String(value).strip_edges())
		elif argument.begins_with("--output-prefix="):
			output_prefix = argument.trim_prefix("--output-prefix=")
		elif argument == "--capture":
			capture = true
		elif argument == "--list-only":
			list_only = true
	_run.call_deferred()


func _run() -> void:
	Engine.max_fps = 60
	# Isolate the scripted Input actions from physical mouse/key events while a
	# native observer window is open; the canonical movement owner still runs.
	root.set_disable_input(true)
	runtime_sources_at_start = _runtime_source_signatures()
	DirAccess.make_dir_recursive_absolute(output_prefix.get_base_dir())
	_collect_inventory()
	if list_only or not failures.is_empty():
		_finish()
		return
	if "--automated-test" in OS.get_cmdline_user_args():
		_fail_once("--automated-test disables canonical movement input")
		_finish()
		return
	if capture and DisplayServer.get_name() == "headless":
		_fail_once("--capture requires a native display")
		_finish()
		return
	# Polling-based gameplay can react during startup before the first fixture
	# frame, so isolate physical bindings before instantiating the real scene.
	_isolate_scripted_input()
	root.size = Vector2i(1280, 800)
	paused = true
	scene = (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	# main._ready reapplies the saved mapping synchronously. Preserve that
	# canonical mapping for restoration, then isolate again before any frame.
	physical_input_bindings.clear()
	_isolate_scripted_input()
	# Flush genuine pre-existing just-pressed/released flags without letting a
	# gameplay consumer interpret the test's input cleanup as an equipment tap.
	await _frames(2)
	paused = false
	await _frames(60)
	player = scene.get_node_or_null("Player") as CharacterBody3D
	controller = scene.get_node_or_null("WeaponController")
	driver = player.get_node_or_null("Mannequin/ProductionAnimation") if player else null
	if player == null or controller == null or driver == null:
		_fail_once("Canonical player, weapon and presentation owners must load")
		_finish()
		return
	_install_fixture()
	for id in selected_ids:
		weapon_id = id
		_release_inputs()
		if not bool(controller.call("apply_authorized_weapon_pickup", "res://config/weapons/%s.json" % id)):
			_fail_once(id + " canonical equip refused")
			continue
		await _frames(90)
		_assert_weapon_visible(id + " equip")
		expected_accepted_shots = _accepted_shot_count()
		for stance in [0, 1]:
			await _check_stance(stance)
		print("FIREARM_TRANSITION_WEAPON ", id, " max_palm_m=", maximum_contacts.get(id, -1.0))
	_finish()


func _collect_inventory() -> void:
	var archived: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Catalog.CATALOG_PATH))
	var extensions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Catalog.EXTENSIONS_PATH))
	var records: Array = archived.get("weapons", []).duplicate(true)
	for id: String in extensions.get("profile_ids", []):
		records.append(JSON.parse_string(FileAccess.get_file_as_string("res://config/weapons/%s.json" % id)))
	var found: Array[String] = []
	for record: Dictionary in records:
		var id := String(record.get("weapon_id", ""))
		var metadata: Dictionary = extensions.get("metadata_overrides", {}).get(id, {})
		var category := String(metadata.get("category", record.get("category", "")))
		if id in EXCLUDED_IDS or category not in FIREARM_CATEGORIES:
			continue
		var path := "res://config/weapons/%s.json" % id
		if not FileAccess.file_exists(path):
			_fail_once(id + " catalog firearm has no saved profile")
			continue
		if id in found:
			_fail_once(id + " duplicate firearm ID")
			continue
		found.append(id)
		var resolved := Contract.load_config(path)
		var handling: Dictionary = resolved.get("handling_profile", {})
		var mechanics := {
			"weapon_id": resolved.get("weapon_id", ""), "ballistics": resolved.get("ballistics", {}),
			"fire_modes": resolved.get("fire_modes", []), "default_fire_mode": resolved.get("default_fire_mode", ""),
			"burst_size": resolved.get("burst_size", 0), "reload_duration_seconds": handling.get("reload_duration_seconds", 0.0),
			"reload_visuals": handling.get("reload_visuals", {}),
		}
		inventory.append({
			"id": id, "original_name": record.get("display_name", id), "category": category,
			"family": handling.get("family", ""), "model": resolved.get("model_fbx", ""),
			"visual_rig": resolved.get("_visual_rig_id", "authored_profile"),
			"training_only": record.get("training_only", false),
			"dynamic_hold": handling.get("dynamic_hold", {}),
			"source_profile_sha256": FileAccess.get_sha256(path),
			"gameplay_contract": mechanics,
			"gameplay_contract_sha256": JSON.stringify(mechanics, "", true).sha256_text(),
		})
		if String(handling.get("family", "")).is_empty():
			_fail_once(id + " shared contract lacks animation family")
	found.sort()
	var expected: Array = EXPECTED_IDS.duplicate()
	expected.sort()
	if found != expected:
		_fail_once("Real firearm inventory differs from expected 33: " + str(found))
	if selected_ids.is_empty():
		selected_ids.assign(found)
	for id in selected_ids:
		if id not in found:
			_fail_once("Requested ID is not a real catalog firearm: " + id)
	print("FIREARM_TRANSITION_INVENTORY real_firearms=", found.size(), " selected=", selected_ids)


func _check_stance(stance: int) -> void:
	_release_inputs()
	# Case setup only. Every measured transition below uses normal input/physics.
	player.global_position = Vector3(500, 0.02, 500)
	player.velocity = Vector3.ZERO
	if not bool(player.call("_try_set_posture", stance)):
		_fail_once(weapon_id + " posture refused: " + str(stance))
		return
	await _frames(100)
	var prefix := "%s_%s" % [weapon_id, "standing" if stance == 0 else "crouched"]
	await _capture_state(prefix + "_idle")
	Input.action_press(&"move_left")
	await _record_transition(prefix + "_A_entry", 28, false)
	_assert_moving(prefix + "_A")
	await _capture_state(prefix + "_A_relaxed")
	if await _accepted_shot(prefix + "_A"):
		await _record_transition(prefix + "_A_fire", 24, true)
		await _capture_state(prefix + "_A_fire")
	Input.action_release(&"move_left")
	Input.action_press(&"move_right")
	await _record_transition(prefix + "_A_to_D", 32, true)
	_assert_moving(prefix + "_D")
	if await _accepted_shot(prefix + "_D"):
		await _record_transition(prefix + "_D_fire", 24, true)
		await _capture_state(prefix + "_D_fire")
	Input.action_release(&"move_right")
	await _record_transition(prefix + "_D_stop_recovery", 110, false)
	await _capture_state(prefix + "_returned_idle")
	var solver: Node = driver.get("weapon_pose_solver")
	if float(driver.get("weapon_ready_weight")) > 0.001 or float(solver.get("authored_stock_release_applied_m")) > 0.00001:
		_fail_once(prefix + " recovery/stock release did not return to idle")


func _accepted_shot(label: String) -> bool:
	var ballistics: Node = controller.get("ballistics")
	if ballistics == null:
		_fail_once(label + " authoritative weapon cadence owner missing")
		return false
	for frame in 240:
		if float(ballistics.get("fire_cooldown")) <= 0.0:
			break
		await _frames(1)
	var before: Dictionary = driver.call("get_animation_debug_state")
	var before_count := int(before.get("fire_upper_body_latch", {}).get("accepted_shot_count", 0))
	if expected_accepted_shots >= 0 and before_count != expected_accepted_shots:
		_fail_once(label + " received an unrequested shot before acceptance")
	var result: Dictionary = controller.call("request_fire")
	if not bool(result.get("fired", false)):
		_fail_once(label + " canonical shot refused: " + JSON.stringify(result))
		return false
	expected_accepted_shots = before_count + 1
	await _frames(1)
	var after: Dictionary = driver.call("get_animation_debug_state")
	var latch: Dictionary = after.get("fire_upper_body_latch", {})
	if int(latch.get("accepted_shot_count", 0)) != before_count + 1 or String(latch.get("owner_state", "")) != "FIRE_RECOVERY":
		_fail_once(label + " accepted shot did not enter the existing recovery owner")
	first_fire_frame_pending = true
	return true


func _record_transition(label: String, count: int, check_bore: bool) -> void:
	for frame in count:
		if first_fire_frame_pending:
			first_fire_frame_pending = false
		else:
			await _frames(1)
		var solver: Node = driver.get("weapon_pose_solver")
		if _accepted_shot_count() != expected_accepted_shots:
			_fail_once(label + " received an unrequested shot during the measured transition")
		var physical := _measure_physical_pose()
		if physical.is_empty():
			_fail_once(label + " actual physical socket measurements unavailable")
			continue
		var authored := bool(solver.get("authored_shoulder_stock_active"))
		var contact := maxf(float(physical.trigger_contact_m), float(physical.support_contact_m))
		maximum_contacts[weapon_id] = maxf(float(maximum_contacts.get(weapon_id, 0.0)), contact)
		var ready := float(driver.get("weapon_ready_weight"))
		var is_pistol := StringName(driver.get("equipped_weapon_family")) == &"TWO_HAND_PISTOL"
		var minimum_angle := PistolDirectionProof.MIN_ELBOW_ANGLE_DEG if is_pistol else float(solver.get("minimum_elbow_angle_deg"))
		var maximum_angle := PistolDirectionProof.MAX_ELBOW_ANGLE_DEG if is_pistol else float(solver.get("maximum_elbow_angle_deg"))
		var left_angle := _physical_elbow_angle(&"Left")
		var right_angle := _physical_elbow_angle(&"Right")
		transition_rows.append({
			"weapon": weapon_id, "state": label, "frame": frame, "ready": ready,
			"physics_frame": Engine.get_physics_frames(),
			"presentation_ready": driver.get("_presentation_ready_weight"),
			"camera_aim_target_world": str(driver.get("visual_aim_target")),
			"reported_bore_error_deg": solver.get("weapon_aim_error_deg"),
			"required_root_correction_deg": solver.get("wrist_correction_deg"),
			"maximum_root_correction_deg": solver.get("maximum_wrist_correction_deg"),
			"speed_mps": Vector2(player.velocity.x, player.velocity.z).length(),
			"physical": physical, "left_elbow_deg": left_angle, "right_elbow_deg": right_angle,
			"authored_stock_active": authored,
			"elbow_acceptance_deg": [minimum_angle, maximum_angle],
		})
		var contact_limit := MAX_AUTHORED_PALM_ERROR_M if authored else MAX_PALM_ERROR_M
		if not is_finite(contact) or contact > contact_limit:
			_fail_once(label + " physical palms exceed %.1f mm" % (contact_limit * 1000.0))
		if ready >= 0.98:
			var bore_limit := MAX_AUTHORED_BORE_ERROR_DEG if authored else MAX_BORE_ERROR_DEG
			if check_bore and float(physical.bore_to_reticle_degrees) > bore_limit:
				_fail_once(label + " ready barrel exceeds %.1f degrees" % bore_limit)
			for angle in [left_angle, right_angle]:
				if not is_finite(angle) or angle < minimum_angle or angle > maximum_angle:
					_fail_once(label + " physical elbow outside saved human bounds")
		if is_pistol:
			if authored or float(solver.get("authored_stock_release_applied_m")) > 0.00001:
				_fail_once(label + " pistol acquired rifle shoulder-stock behavior")
		if capture and label.ends_with("_D_stop_recovery") and frame in [5, 6, 7, 9, 12, 15, 17, 95, 97, 98, 99]:
			await _capture_state(label + "_frame_%02d" % frame)


func _accepted_shot_count() -> int:
	var debug: Dictionary = driver.call("get_animation_debug_state")
	return int(debug.get("fire_upper_body_latch", {}).get("accepted_shot_count", 0))


func _isolate_scripted_input() -> void:
	# Physical key/mouse polling bypasses Viewport.disable_input. Remove only
	# this proof process's bindings, not action names or project-saved mappings.
	for action: StringName in InputMap.get_actions():
		physical_input_bindings[action] = InputMap.action_get_events(action)
		if Input.is_action_pressed(action):
			Input.action_release(action)
		InputMap.action_erase_events(action)


func _restore_physical_input() -> void:
	for action: StringName in physical_input_bindings:
		if Input.is_action_pressed(action):
			Input.action_release(action)
		InputMap.action_erase_events(action)
		for event: InputEvent in physical_input_bindings[action]:
			InputMap.action_add_event(action, event)
	physical_input_bindings.clear()


func _physical_elbow_angle(side: StringName) -> float:
	var solver: Node = driver.get("weapon_pose_solver")
	var upper: Vector3 = solver.call("_bone_world_position", StringName("mixamorig_%sArm" % side))
	var elbow: Vector3 = solver.call("_bone_world_position", StringName("mixamorig_%sForeArm" % side))
	var wrist: Vector3 = solver.call("_bone_world_position", StringName("mixamorig_%sHand" % side))
	return rad_to_deg((upper - elbow).angle_to(wrist - elbow))


func _assert_moving(label: String) -> void:
	if Vector2(player.velocity.x, player.velocity.z).length() < 0.5:
		_fail_once(label + " actual player failed to move")


func _capture_state(label: String) -> void:
	if not capture:
		return
	_assert_weapon_visible(label + " capture")
	var gameplay_camera := root.get_camera_3d()
	await _sample(label)
	if gameplay_camera != null:
		gameplay_camera.current = true


func _assert_weapon_visible(label: String) -> void:
	var weapon: Node3D = driver.weapon_node
	if weapon == null or not weapon.is_visible_in_tree():
		_fail_once(label + " equipped weapon is hidden")
		return
	var visible_meshes := 0
	for node in weapon.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh != null and mesh.is_visible_in_tree():
			visible_meshes += 1
	if visible_meshes == 0:
		_fail_once(label + " equipped weapon has no visible mesh")


func _release_inputs() -> void:
	for action: StringName in [&"move_forward", &"move_left", &"move_right"]:
		if InputMap.has_action(action):
			Input.action_release(action)


func _fail_once(label: String) -> void:
	if not failures.has(label):
		failures.append(label)
		push_error("FIREARM_TRANSITION " + label)


func _finish() -> void:
	_release_inputs()
	_restore_physical_input()
	paused = false
	var report := {
		"canonical_scene": "res://main.tscn", "inventory": inventory,
		"selected_weapons": selected_ids, "list_only": list_only,
		"transitions": transition_rows, "captures": samples,
		"maximum_palm_error_m": maximum_contacts, "failures": failures,
		"pass": failures.is_empty(), "native_visual_approval": false,
		"gameplay_exercised": not list_only and not transition_rows.is_empty(),
		"runtime_sources_at_start": runtime_sources_at_start,
		"runtime_sources_at_finish": _runtime_source_signatures(),
	}
	var output := FileAccess.open(output_prefix + ".json", FileAccess.WRITE)
	if output:
		output.store_string(JSON.stringify(report, "\t"))
		output.close()
	else:
		_fail_once("Could not save report at " + output_prefix)
	print("FIREARM_FAMILY_TRANSITION ", "PASS" if failures.is_empty() else "FAIL", " inventory=", inventory.size(), " selected=", selected_ids.size(), " frames=", transition_rows.size(), " ", failures)
	if scene:
		scene.queue_free()
	quit(0 if failures.is_empty() else 1)


func _runtime_source_signatures() -> Dictionary:
	return {
		"weapon_contract": FileAccess.get_sha256("res://scripts/weapons/weapon_rig_contract.gd"),
		"pose_runtime": FileAccess.get_sha256("res://scripts/player/operator_animation_driver_runtime.gd"),
		"authored_stock": FileAccess.get_sha256("res://scripts/player/operator_weapon_authored_stock_pose.gd"),
		"posture": FileAccess.get_sha256("res://scripts/player/operator_posture_layer.gd"),
	}
