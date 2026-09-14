extends "res://tools/rifle_reference_visual_probe.gd"

## Read-only main proof of saved source default/ready/fire selection.
## The separately labeled ready_api state is a presentation input fixture,
## not a claim that main exposes a persistent player ready button.

var checks := 0
var max_trigger_gap := 0.0
var max_support_gap := 0.0
var transitions: Array[Dictionary] = []


func _initialize() -> void:
	output_prefix = "/private/tmp/source-rifle-default-idle"
	super._initialize()


func _run() -> void:
	if capture and DisplayServer.get_name() == "headless":
		_check(false, "rendered proof requires a display")
		_finish()
		return
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	ProjectSettings.set_setting("socom/session/public_training", true)
	root.size = Vector2i(1280, 800)
	DirAccess.make_dir_recursive_absolute(output_prefix.get_base_dir())
	scene = load("res://main.tscn").instantiate()
	scene.get_node("IndependentCameraRig").capture_mouse_on_ready = false
	root.add_child(scene)
	player = scene.get_node("Player")
	player.set_local_input_enabled(false)
	scene.get_node("IndependentCameraRig").orbit_input_enabled = false
	await _frames(45)
	controller = scene.get_node_or_null("WeaponController")
	driver = player.get_node_or_null("Mannequin/ProductionAnimation")
	_check(controller != null and driver != null, "canonical owners exist")
	if controller == null or driver == null:
		_finish()
		return
	controller.set_input_enabled(false)
	_install_fixture()
	await _frames(40)
	var selected_scene: String = driver.model_root.scene_file_path
	var selected_scale: Vector3 = driver.model_root.scale
	_check(selected_scene == "res://assets/characters/modern_soldier/modern_soldier_iso.scn", "actual selected modern ISO character")
	_check(absf(selected_scale.x - 60.48790231) < .00001, "source-measured visual scale preserved")
	for gun: String in ["m4a1", "ak-47"]:
		weapon_id = gun
		_check(controller.apply_authorized_weapon_pickup("res://config/weapons/" + gun + ".json"), "canonical equip " + gun)
		await _frames(40)
		var graph: AnimationNodeBlendTree = driver.animation_tree.tree_root
		_check(graph.get_node(&"standing_idle_base").animation == &"idle_rifle", "default standing node " + gun)
		_check(driver.animation_player.get_animation(&"idle_rifle").get_meta("source_name", "") == "seal_stand", "original default provenance " + gun)
		_check(graph.get_node(&"source_standing_alert").animation == &"seal_stand_alert02", "ready node remains separate " + gun)
		_check(graph.get_node(&"source_standing_fire").animation == &"seal_fp_stand", "firing node remains separate " + gun)
		for phase: String in ["early", "middle", "late"]:
			await _check_frames(12, gun + " idle " + phase)
			_check(driver.weapon_ready_weight == 0.0 and not driver._fire_upper_body_selected(), "real idle has no ready/fire request " + phase)
			await _sample(gun + "_idle_" + phase)
		# Real weapon controller acceptance, not notify_fired() alone.
		if _request_shot():
			for stage: Array in [[1, "early"], [7, "middle"], [16, "held"]]:
				await _check_frames(int(stage[0]), gun + " shot " + String(stage[1]))
				await _sample(gun + "_fire_" + String(stage[1]))
				if stage[1] == "held":
					_check(driver._fire_upper_body_selected() and driver.weapon_ready_weight > .95, "accepted shot holds ready " + gun)
			# Observe state/weight boundaries rather than assuming render frames are
			# 1/60s; headless and native display can have different process cadence.
			for frame in 240:
				if not driver._fire_upper_body_selected():
					break
				await _check_frames(1, gun + " waiting for natural grace expiry")
			_check(not driver._fire_upper_body_selected(), "natural fire grace expires " + gun)
			await _sample(gun + "_fire_return_early")
			for frame in 120:
				if driver.weapon_ready_weight <= .5:
					break
				await _check_frames(1, gun + " natural return halfway")
			await _sample(gun + "_fire_return_middle")
			for frame in 180:
				if driver.weapon_ready_weight == 0.0 and driver.locomotion_graph.source_standing_fire_weight < .001:
					break
				await _check_frames(1, gun + " natural return tail")
			await _sample(gun + "_fire_return_late")
			_check(not driver._fire_upper_body_selected() and driver.weapon_ready_weight == 0.0, "timer naturally returns to default " + gun)
			_check(driver.locomotion_graph.source_standing_fire_weight < .001, "fire blend naturally returns " + gun)
		# Separate saved ready clip exercise through the existing presentation API.
		# No animation time, bone pose, graph or profile is overwritten here.
		var mannequin: Node = player.get_node("Mannequin")
		mannequin.set_process(false)
		driver.set_visual_inputs(Vector2.ZERO, &"STANDING", driver.aim_yaw_rad, driver.aim_pitch_rad, 1.0, false, 0.0, 0.0, &"LOCOMOTION", 0.0, &"WALK", 0.0, driver.visual_aim_target)
		await _check_frames(45, gun + " ready API")
		_check(driver.weapon_ready_weight > .99 and not driver._fire_upper_body_selected(), "ready API selects alert without accepted fire " + gun)
		await _sample(gun + "_ready_api")
		mannequin.set_process(true)
		await _check_frames(75, gun + " ready API release")
		_check(driver.weapon_ready_weight == 0.0, "main forwarding restores default " + gun)
		_check(driver.model_root.scene_file_path == selected_scene and driver.model_root.scale == selected_scale, "character identity and scale unchanged " + gun)
		var capsule: CapsuleShape3D = player.get_node("CollisionShape3D").shape
		_check(is_equal_approx(capsule.height, 1.85) and is_equal_approx(capsule.radius, .38) and player.scale == Vector3.ONE, "movement capsule and owner unscaled " + gun)
	print("SOURCE_RIFLE_DEFAULT_IDLE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " trigger_max_m=", max_trigger_gap, " support_max_m=", max_support_gap)
	_finish()


func _check_frames(count: int, label: String) -> void:
	for frame in count:
		await _frames(1)
		var measured := _measure_physical_pose()
		var trigger: float = measured.get("trigger_contact_m", INF)
		var support: float = measured.get("support_contact_m", INF)
		max_trigger_gap = maxf(max_trigger_gap, trigger)
		max_support_gap = maxf(max_support_gap, support)
		_check(is_finite(trigger) and trigger < .01, label + " trigger contact frame=" + str(frame))
		_check(is_finite(support) and support < .01, label + " support contact frame=" + str(frame))
		_check(player.is_on_floor(), label + " actual body remains grounded")
		var ready: float = driver.weapon_ready_weight
		var fire: float = driver.locomotion_graph.source_standing_fire_weight
		_check(is_finite(ready) and ready >= 0.0 and ready <= 1.0 and is_finite(fire) and fire >= 0.0 and fire <= 1.0, label + " bounded transition")
		transitions.append({"label": label, "frame": Engine.get_process_frames(), "ready": ready, "fire": fire, "trigger_m": trigger, "support_m": support})


func _sample(label: String) -> void:
	await super._sample(label)
	var row: Dictionary = samples.back()
	row["default_source"] = "seal_stand"
	row["ready_source"] = "seal_stand_alert02"
	row["fire_source"] = "seal_fp_stand"
	row["ready_api_fixture_only"] = label.ends_with("ready_api")
	row["known_limit"] = "Retargeted modern character with existing wrist/socket fitting, not original skinned pose equivalence."


func _finish() -> void:
	var output := FileAccess.open(output_prefix + "-transitions.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify({"checks": checks, "trigger_max_m": max_trigger_gap, "support_max_m": max_support_gap, "transitions": transitions}, "\t"))
	else:
		_check(false, "transition report writable")
	super._finish()


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("SOURCE_RIFLE_IDLE_FAIL " + label)
