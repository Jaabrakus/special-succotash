extends "res://tools/rifle_reference_visual_probe.gd"

const Tuning := preload("res://scripts/runtime/operator_tuning_profile.gd")
const TARGET_SCENE := "res://assets/characters/modern_soldier/modern_soldier_iso.scn"
const SOURCE_SCALE := 60.48790231
var checks := 0

class DriverSpy extends RefCounted:
	var model_root: Node3D = Node3D.new()
	var transition_blend_seconds := 0.0
	var dive_roll_trim_duration := 0.0
	var roll_trim_duration := 0.0
	var received_scale := 0.0
	func set_trooper_scale(value: float) -> void:
		received_scale = value


func _initialize() -> void:
	weapon_id = "m4a1"
	output_prefix = "/private/tmp/source-character-scale-proof"
	super._initialize()


func _run() -> void:
	_test_saved_contract()
	if not failures.is_empty():
		_finish()
		return
	if capture and DisplayServer.get_name() == "headless":
		_check(false, "rendered proof requires native display")
		_finish()
		return
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	ProjectSettings.set_setting("socom/session/public_training", true)
	root.size = Vector2i(1280, 800)
	scene = load("res://main.tscn").instantiate()
	scene.get_node("IndependentCameraRig").capture_mouse_on_ready = false
	root.add_child(scene)
	player = scene.get_node("Player")
	player.set_local_input_enabled(false)
	scene.get_node("IndependentCameraRig").orbit_input_enabled = false
	await _frames(45)
	controller = scene.get_node_or_null("WeaponController")
	driver = player.get_node_or_null("Mannequin/ProductionAnimation")
	_check(controller != null and driver != null, "canonical main owners initialized")
	if controller == null or driver == null:
		_finish()
		return
	controller.set_input_enabled(false)
	_install_fixture()
	await _frames(30)
	_check(driver.model_root.scene_file_path == TARGET_SCENE, "actual selected model matches scoped scene")
	_check(absf(driver.model_root.scale.x - SOURCE_SCALE) < 0.00001, "main consumes saved measured scale")
	_check(player.scale.is_equal_approx(Vector3.ONE), "CharacterBody transform never scaled")
	var skeleton: Skeleton3D = driver.skeleton
	var head := skeleton.get_bone_global_rest(skeleton.find_bone("mixamorig_Head")).origin
	var left := skeleton.get_bone_global_rest(skeleton.find_bone("mixamorig_LeftFoot")).origin
	var right := skeleton.get_bone_global_rest(skeleton.find_bone("mixamorig_RightFoot")).origin
	var span := (skeleton.global_basis * (head - (left + right) * 0.5)).y
	_check(absf(span - 1.6520608432898) < 0.0001, "measured source head-to-ankle span within0.1mm")
	print("SOURCE_SCALE_MAIN span_m=", span, " scale=", driver.model_root.scale)
	for gun in ["m4a1", "mark_23"]:
		weapon_id = gun
		_check(controller.apply_authorized_weapon_pickup("res://config/weapons/" + gun + ".json"), "canonical equip " + gun)
		await _frames(35)
		for stance in [0, 1, 2]:
			_check(player.call("_try_set_posture", stance), "canonical posture " + str(stance))
			await _frames(45)
			var capsule: CapsuleShape3D = player.get_node("CollisionShape3D").shape
			_check(absf(capsule.height - [1.85, 1.25, 0.82][stance]) < 0.00001 and absf(capsule.radius - .38) < .00001, "unchanged movement capsule " + str(stance))
			_check(player.is_on_floor(), "real movement owner remains grounded")
			await _sample(gun + "_" + str(stance) + "_idle")
			if _request_shot():
				for phase in [1, 8, 20]:
					await _frames(1 if phase == 1 else 7 if phase == 8 else 12)
					var physical := _measure_physical_pose()
					_check(not physical.is_empty() and float(physical.get("trigger_contact_m", INF)) < .025, "scaled trigger follows palm " + gun + "/" + str(stance) + "/" + str(phase))
					if phase == 20:
						await _sample(gun + "_" + str(stance) + "_fire_settled")
			await _frames(95)
	print("SOURCE_CHARACTER_SCALE_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	_finish()


func _test_saved_contract() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/operator_movement_tuning.json"))
	var document := Tuning.merge_with_defaults(raw)
	var original := document.duplicate(true)
	var spy := DriverSpy.new()
	spy.model_root.scene_file_path = TARGET_SCENE
	_check(is_equal_approx(Tuning.operator_scale(document, spy), SOURCE_SCALE), "exact selected scene resolves override")
	Tuning.apply(document, null, spy)
	_check(is_equal_approx(spy.received_scale, SOURCE_SCALE), "existing tuning application calls sole visual writer")
	for other in ["", "res://other/modern_soldier_iso.scn", "res://assets/characters/modern_soldier/modern_soldier.scn", "res://assets/characters/ps1_dual_source_rig/ps1_dual_source_rig.scn"]:
		spy.model_root.scene_file_path = other
		_check(Tuning.operator_scale(document, spy) == 64.0, "other model retains global64: " + other)
	_check(Tuning.operator_scale(document, null) == 64.0, "missing visual owner retains global64")
	spy.model_root.scene_file_path = TARGET_SCENE
	for bad in [NAN, INF, -INF, -1.0, 0.0, "60.48", {}, []]:
		var candidate := document.duplicate(true)
		candidate.animation.operator_scale_by_scene[TARGET_SCENE] = bad
		_check(Tuning.operator_scale(candidate, spy) == 64.0, "malformed override falls back")
		_check(document == original, "candidate clone cannot change shared input")
	var edited := document.duplicate(true)
	_check(Tuning.set_operator_scale(edited, spy, 61.25), "studio saves selected override")
	_check(edited.animation.operator_scale == 64.0 and edited.animation.operator_scale_by_scene[TARGET_SCENE] == 61.25, "selected edit preserves global fallback")
	_check(document == original, "selected save does not mutate source clone")
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(edited))
	_check(Tuning.operator_scale(roundtrip, spy) == 61.25, "saved selected value round-trips through runtime")
	spy.model_root.scene_file_path = "res://assets/characters/modern_soldier/modern_soldier.scn"
	Tuning.set_operator_scale(edited, spy, 65.0)
	_check(edited.animation.operator_scale == 65.0 and edited.animation.operator_scale_by_scene[TARGET_SCENE] == 61.25, "other model edit changes fallback only")
	var before := edited.duplicate(true)
	_check(not Tuning.set_operator_scale(edited, spy, NAN) and edited == before, "invalid editor scale leaves save unchanged")
	spy.model_root.free()


func _sample(label: String) -> void:
	await super._sample(label)
	var row: Dictionary = samples.back()
	row["selected_model"] = driver.model_root.scene_file_path
	row["measured_model_scale"] = driver.model_root.scale.x
	row["known_limit"] = "Source skeleton size only; camera markers and crouch/prone ground penetration unchanged."


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("SOURCE_SCALE_FAIL " + label)
