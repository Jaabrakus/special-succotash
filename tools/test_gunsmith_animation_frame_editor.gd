extends SceneTree

const FrameEditor := preload("res://scripts/labs/gunsmith/gunsmith_animation_frame_editor.gd")
const FrameRuntime := preload("res://scripts/player/operator_animation_frame_pose_runtime.gd")


func _init() -> void:
	var editor := FrameEditor.new()
	editor.begin("fire_standing", &"combat_fire", 1.0)
	editor.set_time(0.5)
	var pose := {
		"joint_rotations": {"spine2": {"x": 3.0, "y": 1.0, "z": 0.0}},
		"right_elbow_pole": {"x": 0.1, "y": 0.0, "z": -0.1},
	}
	editor.store_current_pose(pose)
	if editor.frame_index() != 15 or editor.current_pose() != pose:
		push_error("[GUNSMITH FRAME EDITOR] Frame 15 pose did not round-trip.")
		quit(1)
		return
	editor.step_frames(1)
	if editor.frame_index() != 16 or editor.has_current_pose() or editor.sampled_pose() != pose:
		push_error("[GUNSMITH FRAME EDITOR] A single correction key did not hold forward.")
		quit(1)
		return
	var saved := editor.save_data()
	var reloaded := FrameEditor.new()
	reloaded.load_data(saved)
	reloaded.begin("fire_standing", &"combat_fire", 1.0)
	reloaded.set_time(0.5)
	if reloaded.current_pose() != pose:
		push_error("[GUNSMITH FRAME EDITOR] Saved metadata did not reload.")
		quit(1)
		return
	var blend_editor := FrameEditor.new()
	blend_editor.begin("idle_standing", &"aim_idle", 1.0)
	blend_editor.set_time(0.0)
	blend_editor.store_current_pose({
		"joint_rotations": {"spine2": {"x": 0.0, "y": 0.0, "z": 0.0}},
		"right_elbow_pole": {"x": 0.0, "y": 0.0, "z": 0.0},
	})
	blend_editor.set_time(1.0)
	blend_editor.store_current_pose({
		"joint_rotations": {"spine2": {"x": 10.0, "y": 0.0, "z": 0.0}},
		"right_elbow_pole": {"x": 0.2, "y": 0.0, "z": 0.0},
	})
	blend_editor.set_time(0.5)
	var blended := blend_editor.sampled_pose()
	if absf(float(blended["joint_rotations"]["spine2"]["x"]) - 5.0) > 0.001:
		push_error("[GUNSMITH FRAME EDITOR] Pose keys did not interpolate between frames.")
		quit(1)
		return
	blend_editor.set_time(1.0)
	blend_editor.step_frames(1)
	if absf(float(blend_editor.sampled_pose()["joint_rotations"]["spine2"]["x"]) - 10.0) > 0.001:
		push_error("[GUNSMITH FRAME EDITOR] Final correction key did not hold to the clip end.")
		quit(1)
		return
	var runtime := FrameRuntime.new()
	runtime.configure(blend_editor.save_data())
	var runtime_tail: Dictionary = runtime.sample(["aim_idle"], 2.0)
	if absf(float(runtime_tail["joint_rotations"]["spine2"]["x"]) - 10.0) > 0.001:
		push_error("[GUNSMITH FRAME EDITOR] Runtime did not preserve the editor's endpoint curve.")
		quit(1)
		return
	print("[GUNSMITH FRAME EDITOR] PASS: correction keys persist, hold, and interpolate.")
	quit(0)
