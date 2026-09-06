extends "res://tools/pistol_compressed_idle_regression.gd"

## Canonical saved-profile proof, not a candidate pose injection. The observer
## camera affects captures only; gameplay aim and physical contacts stay live.
const PISTOL_IDS := ["mark_23", "226", "9mm_pistol", "de__50", "f57", "m9", "mark_23sd", "model_18"]
var family_weapon_id: String = ""
var baseline_only: bool = false


func _run() -> void:
	Engine.max_fps = 60
	_check_published_contracts()
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	baseline_only = "--baseline" in OS.get_cmdline_user_args()
	var selected: Array = PISTOL_IDS.duplicate()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--weapons="):
			selected = Array(arg.trim_prefix("--weapons=").split(","))
	if capture_enabled and DisplayServer.get_name() == "headless":
		_expect(false, "capture requires a display")
		_finish()
		return
	active_scene = (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(active_scene)
	await _frames(60)
	var player := active_scene.get_node("Player") as CharacterBody3D
	var controller := active_scene.get_node("WeaponController")
	var mannequin := player.get_node("Mannequin")
	var driver := mannequin.get("production_animation") as Node
	player.set_physics_process(false)
	mannequin.set_process(false)
	if capture_enabled:
		_hide_canvas_layers(active_scene)
		var debug_node := active_scene.find_child("CameraBoomVisualizer", true, false) as Node3D
		if debug_node != null:
			debug_node.visible = false
		mannequin.call("set_proxy_visuals_visible", false)
		review_camera = Camera3D.new()
		review_camera.fov = 38.0
		review_camera.set_cull_mask_value(20, false)
		active_scene.add_child(review_camera)
	for weapon_id in selected:
		family_weapon_id = String(weapon_id)
		_expect(family_weapon_id in PISTOL_IDS, family_weapon_id + " is a catalog pistol")
		_expect(bool(controller.call("apply_authorized_weapon_pickup", "res://config/weapons/%s.json" % weapon_id)), family_weapon_id + " canonical equip")
		await _frames(30)
		if baseline_only:
			driver.call("clear_fire_ready_aim")
			player.call("_try_set_posture", 0)
			var target := player.global_position + Vector3.UP * 1.48 + _world_aim_direction(player, 0.0, 0.0) * 25.0
			driver.call("set_visual_inputs", Vector2.ZERO, &"STANDING", 0.0, 0.0, 0.0, false, 0.0, 0.0, &"LOCOMOTION", 0.0, &"WALK", 0.0, target, Vector2.ZERO, 0.0, &"IDLE", 0.0)
			await _frames(60)
			_report_sample(family_weapon_id, "baseline", _compressed_sample(driver))
			print("PISTOL_FAMILY_BASELINE %s clip=%s" % [weapon_id, driver.call("_select_visual_clip")])
			await _capture_pair(driver, player, "standing", "idle")
			continue
		var profile: Dictionary = driver.get("equipped_weapon_handling_profile")
		var slots: Dictionary = profile.get("animation_slots", {})
		_expect(String(slots.get("idle_standing", "")) == "pistol_compressed_idle_standing", family_weapon_id + " inherits approved standing idle")
		_expect(String(slots.get("ready_standing_moving", "")) == "pistol_idle" and String(slots.get("ready_crouched_moving", "")) == "pistol_idle_kneeling", family_weapon_id + " preserves moving source clips")
		for posture in [0, 1]:
			await _check_compressed_cycle(player, controller, driver, posture, Vector2.ZERO)
			await _check_reload_owner(player, controller, driver, posture)
		await _check_compressed_cycle(player, controller, driver, 0, Vector2(AIM_YAW_RAD, AIM_PITCH_RAD))
	active_scene.queue_free()
	await process_frame
	_finish()


func _check_published_contracts() -> void:
	var publisher := load("res://tools/publish_firearm_family_visual_rigs.gd").new() as SceneTree
	var expected: Dictionary = publisher.call("_handling_profile", "TWO_HAND_PISTOL", "pistol")
	for index in range(1, 7):
		var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapon_visual_rigs/family_pistol_%d_v2.json" % index))
		var current: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapon_visual_rigs/family_pistol_%d_v3.json" % index))
		_expect(current["visual"]["handling_profile"] == expected, "model %d publisher and saved handling agree" % index)
		for key in old["visual"]:
			if key != "handling_profile":
				_expect(old["visual"][key] == current["visual"][key], "model %d preserves %s" % [index, key])
		_expect(old["calibration"] == current["calibration"], "model %d preserves calibration" % index)
	publisher.free()


func _capture_pair(driver: Node, player: CharacterBody3D, label: String, phase: String) -> void:
	if not capture_enabled:
		return
	var prefix := "/private/tmp/pistol-family-%s-%s-%s-%s" % ["before" if baseline_only else "after", family_weapon_id, label.to_lower(), phase]
	_aim_review_camera(review_camera, driver, player)
	_expect(await _capture(prefix + "-side.png"), label + " " + phase + " side capture")
	_aim_rear_camera(review_camera, driver, player)
	_expect(await _capture(prefix + "-rear.png"), label + " " + phase + " rear capture")
	await _frames(4)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(family_weapon_id + ": " + label)
		push_error("PISTOL_FAMILY_IDLE FAIL %s: %s" % [family_weapon_id, label])


func _report_sample(label: String, phase: String, sample: Dictionary) -> void:
	super._report_sample(family_weapon_id + "_" + label, phase, sample)


func _finish() -> void:
	print("PISTOL_FAMILY_IDLE %s failures=%d %s" % ["PASS" if failures.is_empty() else "FAIL", failures.size(), failures])
	quit(0 if failures.is_empty() else 1)
