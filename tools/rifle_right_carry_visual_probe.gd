extends "res://tools/rifle_reference_visual_probe.gd"

func _run() -> void:
	if capture and DisplayServer.get_name() == "headless":
		failures.append("Native display required for captures")
		_finish()
		return
	root.size = Vector2i(1280, 800)
	scene = (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	await _frames(60)
	player = scene.get_node("Player") as CharacterBody3D
	controller = scene.get_node("WeaponController")
	driver = player.get_node("Mannequin/ProductionAnimation")
	_install_fixture()
	if not bool(controller.call("apply_authorized_weapon_pickup", "res://config/weapons/%s.json" % weapon_id)):
		failures.append("Canonical equip failed")
		_finish()
		return
	await _frames(100)
	for stance: int in [0, 1]:
		Input.action_release(&"move_right")
		player.global_position = Vector3(500, 0.02, 500)
		player.velocity = Vector3.ZERO
		player.call("_try_set_posture", stance)
		await _frames(100)
		var prefix := "standing" if stance == 0 else "crouched"
		await _sample(prefix + "_idle")
		Input.action_press(&"move_right")
		await _frames(60)
		await _sample(prefix + "_move_right")
		if _request_shot():
			await _frames(6)
			await _sample(prefix + "_move_right_fire_entry")
			await _frames(24)
			await _sample(prefix + "_move_right_fire_settled")
		Input.action_release(&"move_right")
		await _frames(100)
		await _sample(prefix + "_returned_idle")
	_finish()
