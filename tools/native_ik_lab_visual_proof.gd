extends SceneTree

const OUTPUT_DIRECTORY := "/private/tmp/socom-new-ik-lab-proof"
const HOLD_IMAGE := OUTPUT_DIRECTORY + "/rifle_hold.png"
const FIRE_IMAGE := OUTPUT_DIRECTORY + "/combat_fire.png"

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIRECTORY)
	root.size = Vector2i(1440, 900)
	var packed := load("res://scenes/labs/native_ik_player_lab.tscn") as PackedScene
	_expect(packed != null, "New IK Lab scene loads")
	if packed == null:
		_finish()
		return
	var lab := packed.instantiate() as Node3D
	root.add_child(lab)
	await _frames(140)
	var player := lab.get_node("Player") as CharacterBody3D
	var skeleton := player.get_node("Model/GeneralSkeleton") as Skeleton3D
	var gun := player.get_node(
		"Model/GeneralSkeleton/RShoulderBoneAttachment3D2/WeaponHolder/Gun"
	) as Node3D
	var support_target := gun.get_node("LHikTarget") as Node3D
	var left_hand_ik := skeleton.get_node("LHTwoBoneIK3D") as TwoBoneIK3D
	var camera := player.get_node("Camera/CameraTarget/SpringArm3D/Camera3D") as Camera3D
	camera.current = false
	var review_camera := Camera3D.new()
	review_camera.name = "ProofCamera"
	lab.add_child(review_camera)
	review_camera.fov = 42.0
	review_camera.global_position = player.global_position + Vector3(2.2, 1.45, 2.2)
	review_camera.look_at(player.global_position + Vector3(0.0, 1.15, 0.0), Vector3.UP)
	review_camera.current = true
	await _frames(20)
	_expect(
		left_hand_ik.get_node(left_hand_ik.get_target_node(0)) == support_target
		and is_equal_approx(left_hand_ik.influence, 1.0),
		"purchased support-hand IK is bound to Gun/LHikTarget"
	)
	await _capture(HOLD_IMAGE)

	var fire_started := bool(player.call("notify_operator_fired"))
	await _frames(4)
	var animation_tree := player.get_node("AnimationTree") as AnimationTree
	_expect(
		animation_tree.active
		and bool(animation_tree.get("parameters/CombatFireUpperBody/active"))
		and is_equal_approx(left_hand_ik.influence, 1.0),
		"combat fire runs while purchased gun-contact IK remains active"
	)
	_expect(fire_started, "accepted-fire event starts the combat-fire layer")
	await _capture(FIRE_IMAGE)
	print(
		"NATIVE_IK_LAB_VISUAL_METRICS hold=%s combat_fire=%s target=%s"
		% [HOLD_IMAGE, FIRE_IMAGE, support_target.get_path()]
	)
	_finish()


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var result := image.save_png(path)
	_expect(result == OK, "captured %s" % path.get_file())


func _frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _physics_frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("NATIVE_IK_LAB_VISUAL PASS ", label)
	else:
		failures.append(label)
		push_error("NATIVE_IK_LAB_VISUAL FAIL " + label)


func _finish() -> void:
	if failures.is_empty():
		print("NATIVE_IK_LAB_VISUAL_PROOF PASS")
		quit(0)
	else:
		print("NATIVE_IK_LAB_VISUAL_PROOF FAIL ", failures)
		quit(1)
