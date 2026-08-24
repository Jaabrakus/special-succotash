extends SceneTree

const FramePoseRuntime := preload(
	"res://scripts/player/operator_animation_frame_pose_runtime.gd"
)


func _initialize() -> void:
	var runtime = FramePoseRuntime.new()
	runtime.configure({
		"aim_idle": {
			"0": {
				"joint_rotations": {"head": {"x": 0.0, "y": 0.0, "z": 0.0}},
				"right_elbow_pole": {"x": 0.0, "y": 0.0, "z": 0.0},
			},
			"30": {
				"joint_rotations": {"head": {"x": 10.0, "y": 20.0, "z": 30.0}},
				"right_elbow_pole": {"x": 0.2, "y": 0.4, "z": 0.6},
			},
		},
	})
	var midpoint: Dictionary = runtime.sample([&"aim_idle"], 0.5)
	var head: Dictionary = (midpoint.get("joint_rotations", {}) as Dictionary).get("head", {})
	var elbow: Dictionary = midpoint.get("right_elbow_pole", {})
	if (
		absf(float(head.get("y", -1.0)) - 10.0) > 0.001
		or absf(float(elbow.get("z", -1.0)) - 0.3) > 0.001
		or runtime.key_count() != 2
	):
		push_error("[FRAME POSE RUNTIME] FAIL: saved pose interpolation contract broke")
		quit(1)
		return
	var outside: Dictionary = runtime.sample([&"aim_idle"], 1.5)
	var outside_head: Dictionary = (
		outside.get("joint_rotations", {}) as Dictionary
	).get("head", {})
	if absf(float(outside_head.get("y", -1.0)) - 20.0) > 0.001:
		push_error("[FRAME POSE RUNTIME] FAIL: terminal correction did not hold to clip end")
		quit(1)
		return
	print("[FRAME POSE RUNTIME] PASS: saved correction keys interpolate and hold to clip bounds.")
	quit(0)
