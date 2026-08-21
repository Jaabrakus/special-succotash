extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://tactical_grenade_lab.tscn") as PackedScene
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	for _frame in 20:
		await process_frame
	var camera := scene.get("camera") as Camera3D
	var model := scene.get("operator_model") as Node3D
	var skeleton := scene.get("operator_skeleton") as Skeleton3D
	if camera != null and model != null:
		print("GRENADE_LAB_CAMERA ", camera.global_position, " MODEL ", model.global_position, " SCREEN ", camera.unproject_position(model.global_position), " BEHIND ", camera.is_position_behind(model.global_position))
	if camera != null and skeleton != null:
		var head_index := skeleton.find_bone("mixamorig_Head")
		if head_index >= 0:
			var head_position := (skeleton.global_transform * skeleton.get_bone_global_pose(head_index)).origin
			print("GRENADE_LAB_HEAD ", head_position, " SCREEN ", camera.unproject_position(head_position), " BEHIND ", camera.is_position_behind(head_position))
	scene.call("_throw_grenade")
	await create_timer(0.55).timeout
	var grenade := scene.get("active_preview_grenade") as TacticalGrenadeBase
	if grenade != null:
		grenade.detonate()
	await create_timer(1.25).timeout
	var image := root.get_texture().get_image()
	image.save_png("/private/tmp/141-grenade-lab-render.png")
	print("GRENADE_LAB_CAPTURE /private/tmp/141-grenade-lab-render.png")
	quit(0)
