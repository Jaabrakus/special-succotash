extends SceneTree

const MainScene := preload("res://main.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := MainScene.instantiate()
	root.add_child(scene)
	for _frame in 20:
		await physics_frame
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	_expect(player != null, "canonical player exists")
	if player == null:
		_finish()
		return
	player.velocity = Vector3.ZERO
	Input.action_press(&"move_right", 1.0)
	await physics_frame
	Input.action_release(&"move_right")
	var first_frame_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_expect(bool(player.get("instant_strafe_response")), "instant strafe response is enabled")
	_expect(
		float(player.get("strafe_speed")) >= float(player.get("move_speed")),
		"strafe has no lower speed cap"
	)
	_expect(
		first_frame_speed >= float(player.get("strafe_speed")) * 0.99,
		"A/D reaches full strafe speed in one physics frame"
	)
	player.velocity = Vector3.RIGHT * float(player.get("strafe_speed"))
	Input.action_press(&"move_left", 1.0)
	await physics_frame
	Input.action_release(&"move_left")
	_expect(player.velocity.x < -float(player.get("strafe_speed")) * 0.99, "opposite strafe reverses in one physics frame")
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("INSTANT_STRAFE_CHECK PASS ", label)
	else:
		failures.append(label)


func _finish() -> void:
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	if failures.is_empty():
		print("INSTANT_STRAFE_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("INSTANT_STRAFE_REGRESSION: %s" % failure)
	quit(1)
