extends SceneTree

const MAIN_SCENE := preload("res://main.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	for _frame in 12:
		await process_frame

	_expect(_action_has_key(&"reload_weapon", KEY_R), "R belongs to weapon reload")
	_expect(not _action_has_key(&"reset_camera", KEY_R), "R no longer resets the camera")
	_expect(_action_has_key(&"reset_camera", KEY_HOME), "Home owns manual camera reset")
	var camera_rig: Node3D = main.get("camera_rig") as Node3D
	var yaw_before := float(camera_rig.get("yaw")) if camera_rig else 0.0
	_expect(bool(main.call("_request_weapon_reload")), "reload input starts the equipped reload action")
	var mannequin := main.get("player").get_node_or_null("Mannequin") as Node
	var driver: Node = mannequin.get("production_animation") as Node if mannequin else null
	_expect(
		driver != null and "reload" in String(driver.get("requested_action")).to_lower(),
		"reload uses the posture-aware equipped animation"
	)
	_expect(
		camera_rig != null and is_equal_approx(float(camera_rig.get("yaw")), yaw_before),
		"reload does not move camera yaw"
	)

	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("RELOAD_INPUT_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("RELOAD_INPUT_REGRESSION: %s" % failure)
	quit(1)


func _action_has_key(action: StringName, keycode: Key) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return true
	return false


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
