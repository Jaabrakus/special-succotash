extends SceneTree

const PoseEditor := preload("res://scripts/labs/animation_pose_editor.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var skeleton := Skeleton3D.new()
	skeleton.add_bone("hips")
	skeleton.add_bone("hand")
	skeleton.set_bone_parent(1, 0)
	skeleton.set_bone_pose_position(0, Vector3(0.0, 1.0, 0.0))
	skeleton.set_bone_pose_rotation(1, Quaternion(Vector3.UP, 0.2))
	var editor = PoseEditor.new()
	_expect(editor.capture_pose(skeleton, 0) == 0, "first imported-frame pose is captured")
	skeleton.set_bone_pose_position(0, Vector3(0.1, 1.1, 0.0))
	skeleton.set_bone_pose_rotation(1, Quaternion(Vector3.UP, 0.7))
	_expect(editor.capture_pose(skeleton, 6) == 1, "second stop-motion pose is captured")
	_expect(editor.copy_latest_pose(), "pose can be copied")
	skeleton.reset_bone_poses()
	_expect(editor.paste_pose(skeleton), "copied pose can be pasted onto the skeleton")
	_expect(is_equal_approx(skeleton.get_bone_pose_position(0).x, 0.1), "pasted pose restores bone translation")
	var animation: Animation = editor.build_animation(NodePath("Skeleton3D"), 30.0, true)
	_expect(animation != null, "captured poses bake into an authored animation")
	if animation != null:
		_expect(animation.get_track_count() == 6, "position rotation and scale are baked for each bone")
		_expect(is_equal_approx(animation.length, 0.2), "pose frames retain their output timing")
		_expect(animation.track_get_key_count(0) == 2, "baked tracks contain both key poses")
	_finish()


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("POSE_EDITOR_CHECK PASS ", message)
	else:
		failures.append(message)
		push_error("POSE_EDITOR_CHECK FAIL %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("ANIMATION_POSE_EDITOR_REGRESSION PASS")
		quit(0)
	else:
		print("ANIMATION_POSE_EDITOR_REGRESSION FAIL (%d)" % failures.size())
		quit(1)
