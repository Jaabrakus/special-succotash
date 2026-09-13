extends SceneTree

const Modifier := preload("res://scripts/player/operator_traversal_hand_modifier.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/ledge_climb.json"))
	var body := Node3D.new()
	root.add_child(body)
	body.position = Vector3(5, 2, 9)
	var skeleton := Skeleton3D.new()
	body.add_child(skeleton)
	skeleton.add_bone("mixamorig_Hips")
	var modifier := Modifier.new()
	skeleton.add_child(modifier)
	var start := Transform3D(Basis(Vector3.UP, 1.2), Vector3(0, 0.8, 0.1))
	for hz in [30, 60, 120]:
		modifier.track_traversal_exit("vault")
		_set_pose(skeleton, start)
		modifier._capture_exit_pose(skeleton)
		modifier.begin_exit(settings.exit_transition)
		_check(modifier.exit_active and modifier.exit_weight == 1.0, "exit begins at last evaluated pose")
		var elapsed := 0.0
		var previous := 1.0
		while modifier.exit_active:
			var destination := Transform3D(Basis(Vector3.UP, -elapsed), Vector3(elapsed, 0.9, 0))
			_set_pose(skeleton, destination)
			modifier._process_modification()
			var expected := destination.interpolate_with(start, modifier.exit_weight)
			_check(skeleton.get_bone_pose(0).is_equal_approx(expected), "blend uses live destination, not an accumulated previous pose")
			_check(modifier.exit_weight <= previous, "weight decreases monotonically")
			previous = modifier.exit_weight
			modifier.advance_exit(1.0 / hz)
			elapsed += 1.0 / hz
		_check(elapsed <= float(settings.exit_transition.seconds) + 1.0 / hz + 0.00001, "bounded saved duration at " + str(hz) + " Hz")
		_check(not modifier.active and modifier.exit_pose.is_empty(), "no residual pose writer after exit")
		_check(body.position == Vector3(5,2,9), "movement owner untouched")
	modifier.track_traversal_exit("pull_up")
	_set_pose(skeleton, start)
	modifier._capture_exit_pose(skeleton)
	modifier.begin_exit(settings.exit_transition)
	modifier.track_traversal_exit("hang_free")
	_check(not modifier.exit_active and modifier.exit_pose.is_empty(), "new hang cancels old exit")
	modifier.track_traversal_exit("vault")
	modifier._capture_exit_pose(skeleton)
	modifier.begin_exit(settings.exit_transition)
	modifier.cancel_exit()
	_check(not modifier.active and modifier.exit_pose.is_empty(), "death/cancel clears smoothing")
	modifier.elbow_profile = settings.hang_elbow_pole
	modifier.hand_weights.assign([1.0, 1.0])
	for yaw in [0.0, 0.9, -1.5]:
		var normal := Vector3.BACK.rotated(Vector3.UP, yaw)
		modifier.contact_presentation = {"surface_normal": normal}
		for side in 2:
			var outward := normal.cross(Vector3.UP) * (1.0 if side == 0 else -1.0)
			var bend := modifier._elbow_bend(skeleton, Vector3.UP, -outward, side)
			_check(bend.is_finite() and bend.dot(outward) > 0, "supported elbow stays on its own outward side independent of wall yaw")
	modifier.hand_weights.assign([0.0, 0.0])
	_check(modifier._elbow_bend(skeleton, Vector3.UP, Vector3.RIGHT, 0).is_equal_approx(Vector3.RIGHT), "elbow pole releases with hand")
	# A live equip gesture must not be frozen by the lower-body exit snapshot.
	skeleton.add_bone("mixamorig_Spine")
	skeleton.set_bone_parent(1, 0)
	skeleton.add_bone("mixamorig_RightForeArm")
	skeleton.set_bone_parent(2, 1)
	modifier.track_traversal_exit("pull_up")
	skeleton.set_bone_pose_rotation(2, Quaternion.IDENTITY)
	modifier._capture_exit_pose(skeleton)
	modifier.begin_exit(settings.exit_transition)
	modifier.exit_live_upper_body = true
	for hz in [30, 60, 120]:
		var live := Quaternion(Vector3.RIGHT, 1.0 + 1.0 / hz)
		skeleton.set_bone_pose_rotation(2, live)
		modifier._process_modification()
		_check(skeleton.get_bone_pose_rotation(2).is_equal_approx(live), "live upper-body recovery survives full exit weight at " + str(hz) + " Hz")
	modifier.cancel_exit()
	_check(not modifier.exit_live_upper_body, "cancel clears live upper-body ownership")
	body.queue_free()
	await process_frame
	print("TRAVERSAL_EXIT_POSE ", "PASS" if failures.is_empty() else "FAIL", failures)
	quit(0 if failures.is_empty() else 1)

func _set_pose(skeleton: Skeleton3D, pose: Transform3D) -> void:
	skeleton.set_bone_pose_position(0, pose.origin)
	skeleton.set_bone_pose_rotation(0, pose.basis.get_rotation_quaternion())
	skeleton.set_bone_pose_scale(0, pose.basis.get_scale())

func _check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
