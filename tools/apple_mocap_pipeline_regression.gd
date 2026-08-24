extends SceneTree

const MotionProcessor := preload("res://scripts/mocap/apple_mocap_motion_processor.gd")
const OperatorRetargeter := preload("res://scripts/mocap/apple_mocap_operator_retargeter.gd")
const OperatorScene := preload(
	"res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx"
)

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var raw := _synthetic_capture()
	var processed: Dictionary = MotionProcessor.new().process(raw, {
		"maximum_repair_gap_frames": 3,
		"smoothing_passes": 1,
		"target_height_m": 1.80,
	})
	_expect(bool(processed.get("ok", false)), "synthetic Apple capture processes")
	if not bool(processed.get("ok", false)):
		_finish()
		return
	var frames: Array = processed.get("frames", [])
	_expect(frames.size() == 7, "processor preserves the sampled frame count")
	_expect(int(processed.get("repaired_samples", 0)) >= 17, "missing Apple frame is reconstructed")
	_expect(bool(frames[3].get("repaired", false)), "reconstructed frame is marked for review")
	_expect(bool(processed.get("in_place", false)), "processed motion is explicitly in-place")
	_expect(
		(processed.get("motion_features", []) as Array).size() == frames.size(),
		"motion-matching features exist for every frame"
	)
	var repaired_joints: Dictionary = frames[3].get("joints", {})
	_expect(repaired_joints.size() == 17, "reconstructed frame contains all Apple joints")
	var root_position: Dictionary = repaired_joints.get("human_root_3D", {}).get("position", {})
	_expect(
		absf(float(root_position.get("x", 1.0))) <= 0.0001
		and absf(float(root_position.get("z", 1.0))) <= 0.0001,
		"in-place conversion removes horizontal root translation from the pose"
	)
	var feature: Dictionary = (processed.get("motion_features", []) as Array)[2]
	_expect(float(feature.get("speed_mps", 0.0)) > 0.0, "root velocity is retained for future motion matching")
	_expect(
		bool(feature.get("left_foot_contact", false))
		or bool(feature.get("right_foot_contact", false)),
		"processed motion labels planted-foot contact"
	)
	_expect(
		(frames[5].get("bone_rotations", {}) as Dictionary).has("mixamorig_RightForeArm"),
		"joint directions reconstruct an operator forearm rotation"
	)

	var operator := OperatorScene.instantiate()
	var skeleton := _find_skeleton(operator)
	var animation := OperatorRetargeter.new().build_animation(
		processed,
		skeleton,
		NodePath(".")
	)
	print("APPLE_MOCAP_TARGET_BONES ", skeleton.get_bone_count() if skeleton != null else -1)
	_expect(skeleton != null and skeleton.get_bone_count() == 65, "retarget destination is the 65-bone operator")
	_expect(animation != null, "processed Apple motion builds a Godot animation")
	if animation != null:
		_expect(animation.get_track_count() >= 10, "retargeted animation drives the major operator chains")
		_expect(not _has_position_track(animation), "in-place review cannot displace the operator root")
		_expect(_animation_moves_operator(animation, skeleton), "retargeted animation resolves and moves the operator rig")
		_expect(str(animation.get_meta("review_status", "")) == "PENDING", "new capture requires Studio approval")
		_expect(bool(animation.get_meta("in_place", false)), "baked review clip retains in-place metadata")
		_expect(
			(animation.get_meta("motion_features", []) as Array).size() == frames.size(),
			"review clip preserves motion-matching feature metadata"
		)
	var upper_body_animation := OperatorRetargeter.new().build_animation(
		processed,
		skeleton,
		NodePath("."),
		{"include_lower_body": false}
	)
	_expect(upper_body_animation != null, "cropped footage builds an upper-body review clip")
	if upper_body_animation != null:
		_expect(str(upper_body_animation.get_meta("body_regions", "")) == "upper_body_only", "upper-body review declares its safe body region")
		_expect(not _has_lower_body_track(upper_body_animation), "upper-body review leaves hips and legs available for clean Studio layers")
	operator.free()
	_finish()


func _animation_moves_operator(animation: Animation, skeleton: Skeleton3D) -> bool:
	var forearm := skeleton.find_bone("mixamorig_RightForeArm")
	if forearm < 0:
		return false
	var player := AnimationPlayer.new()
	skeleton.add_child(player)
	player.root_node = player.get_path_to(skeleton)
	var library := AnimationLibrary.new()
	library.add_animation(&"review", animation)
	player.add_animation_library("test", library)
	var before := skeleton.get_bone_pose_rotation(forearm)
	player.play(&"test/review")
	player.seek(minf(animation.length, 0.5), true)
	var after := skeleton.get_bone_pose_rotation(forearm)
	player.queue_free()
	return before.angle_to(after) > deg_to_rad(0.1)


func _has_position_track(animation: Animation) -> bool:
	for track_index in range(animation.get_track_count()):
		if animation.track_get_type(track_index) == Animation.TYPE_POSITION_3D:
			return true
	return false


func _has_lower_body_track(animation: Animation) -> bool:
	for track_index in range(animation.get_track_count()):
		var path := str(animation.track_get_path(track_index)).to_lower()
		if "hips" in path or "upleg" in path or "leftleg" in path or "rightleg" in path or "foot" in path:
			return true
	return false


func _synthetic_capture() -> Dictionary:
	var frames: Array[Dictionary] = []
	for frame_index in range(7):
		if frame_index == 3:
			frames.append({
				"frame": frame_index,
				"time": float(frame_index) / 10.0,
				"detected": false,
				"joints": {},
			})
			continue
		var travel := float(frame_index) * 0.018
		var arm_swing := sin(float(frame_index) * 0.55) * 0.12
		var points := {
			"human_root_3D": Vector3(travel, 0.96, 0.0),
			"human_spine_3D": Vector3(travel, 1.22, 0.0),
			"human_center_shoulder_3D": Vector3(travel, 1.48, 0.0),
			"human_center_head_3D": Vector3(travel, 1.66, 0.0),
			"human_top_head_3D": Vector3(travel, 1.80, 0.0),
			"human_left_shoulder_3D": Vector3(travel - 0.22, 1.47, 0.0),
			"human_left_elbow_3D": Vector3(travel - 0.43, 1.22, arm_swing),
			"human_left_wrist_3D": Vector3(travel - 0.50, 0.98, arm_swing + 0.05),
			"human_right_shoulder_3D": Vector3(travel + 0.22, 1.47, 0.0),
			"human_right_elbow_3D": Vector3(travel + 0.43, 1.22, -arm_swing),
			"human_right_wrist_3D": Vector3(travel + 0.50, 0.98, -arm_swing - 0.05),
			"human_left_hip_3D": Vector3(travel - 0.14, 0.93, 0.0),
			"human_left_knee_3D": Vector3(travel - 0.14, 0.50, 0.02),
			"human_left_ankle_3D": Vector3(0.0, 0.05, 0.02),
			"human_right_hip_3D": Vector3(travel + 0.14, 0.93, 0.0),
			"human_right_knee_3D": Vector3(travel + 0.14, 0.50, -0.02),
			"human_right_ankle_3D": Vector3(0.04, 0.05, -0.02),
		}
		var joints := {}
		for joint_name in points:
			joints[joint_name] = {
				"model": _vector_data(points[joint_name]),
				"confidence": 0.95,
			}
		frames.append({
			"frame": frame_index,
			"time": float(frame_index) / 10.0,
			"detected": true,
			"body_height": 1.80,
			"joints": joints,
		})
	return {
		"schema": "socom_apple_body_pose_3d_v1",
		"source_video": "/synthetic/operator_walk.mov",
		"fps": 10.0,
		"duration": 0.6,
		"frame_count": frames.size(),
		"frames": frames,
	}


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _vector_data(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("APPLE_MOCAP_PIPELINE_CHECK PASS ", message)
	else:
		failures.append(message)
		push_error("APPLE_MOCAP_PIPELINE_CHECK FAIL %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("APPLE_MOCAP_PIPELINE_REGRESSION PASS")
	else:
		push_error("APPLE_MOCAP_PIPELINE_REGRESSION FAIL %s" % str(failures))
	quit(0 if failures.is_empty() else 1)
