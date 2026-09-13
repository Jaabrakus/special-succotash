extends "res://tools/traversal_hand_contact_regression.gd"

var captures: Dictionary = {}

func _run() -> void:
	await super._run()
	for path: String in captures:
		captures[path].save_png(path)

func _capture(label: String) -> void:
	var was_paused := paused
	paused = true
	var original := camera.transform
	for angle in (2 if "hang" in label or "exit" in label else 1):
		if angle == 1:
			if "hang" in label:
				camera.global_position = Vector3(500.8, 2.9, 501.2)
				camera.look_at(Vector3(500, 2.57, 500.48))
			else:
				camera.global_position = player.global_position + Vector3(2, 1.4, -3)
				camera.look_at(player.global_position + Vector3.UP)
		camera.force_update_transform()
		RenderingServer.force_draw(false)
		captures["/private/tmp/modern-climb-" + label + "-" + str(angle) + ".png"] = root.get_texture().get_image()
	camera.transform = original
	paused = was_paused
