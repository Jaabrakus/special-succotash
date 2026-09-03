extends SceneTree

const OUTPUT_DIRECTORY := "/private/tmp/socom-new-ik-target-sweep"

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIRECTORY)
	root.size = Vector2i(960, 720)
	var packed := load("res://scenes/labs/native_ik_player_lab.tscn") as PackedScene
	if packed == null:
		quit(1)
		return
	var lab := packed.instantiate() as Node3D
	root.add_child(lab)
	await _frames(120)
	var player := lab.get_node("Player") as CharacterBody3D
	var target := player.get_node("TargetPivot/RHUpperArmWeaponTarget") as Node3D
	var source_rotation := target.rotation
	var source_camera := player.get_node("Camera/CameraTarget/SpringArm3D/Camera3D") as Camera3D
	source_camera.current = false
	var review_camera := Camera3D.new()
	lab.add_child(review_camera)
	review_camera.fov = 42.0
	review_camera.global_position = player.global_position + Vector3(2.2, 1.45, 2.2)
	review_camera.look_at(player.global_position + Vector3(0.0, 1.15, 0.0), Vector3.UP)
	review_camera.current = true
	for entry in [
		["base", Vector3.ZERO],
		["x_pos_67", Vector3(67.377, 0.0, 0.0)],
		["x_neg_67", Vector3(-67.377, 0.0, 0.0)],
		["y_pos_67", Vector3(0.0, 67.377, 0.0)],
		["y_neg_67", Vector3(0.0, -67.377, 0.0)],
		["z_pos_67", Vector3(0.0, 0.0, 67.377)],
		["z_neg_67", Vector3(0.0, 0.0, -67.377)],
	]:
		target.rotation = source_rotation + Vector3(
			deg_to_rad(entry[1].x),
			deg_to_rad(entry[1].y),
			deg_to_rad(entry[1].z)
		)
		await _frames(8)
		await RenderingServer.frame_post_draw
		var path := "%s/%s.png" % [OUTPUT_DIRECTORY, entry[0]]
		var result := root.get_texture().get_image().save_png(path)
		if result != OK:
			failures.append(path)
	print("NATIVE_IK_TARGET_SWEEP output=%s" % OUTPUT_DIRECTORY)
	quit(0 if failures.is_empty() else 1)


func _frames(count: int) -> void:
	for _frame in range(count):
		await process_frame
