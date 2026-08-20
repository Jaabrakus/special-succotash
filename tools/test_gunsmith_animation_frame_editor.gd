extends SceneTree

const FrameEditor := preload("res://scripts/labs/gunsmith/gunsmith_animation_frame_editor.gd")
const FrameRuntime := preload("res://scripts/player/operator_animation_frame_pose_runtime.gd")
const WeaponPoseSolver := preload("res://scripts/player/operator_weapon_pose_solver.gd")


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
		"weapon_hand_position_correction": {"x": 0.0, "y": 0.0, "z": 0.0},
		"weapon_hand_rotation_correction_deg": {"x": 0.0, "y": 0.0, "z": 0.0},
	})
	blend_editor.set_time(1.0)
	blend_editor.store_current_pose({
		"joint_rotations": {"spine2": {"x": 10.0, "y": 0.0, "z": 0.0}},
		"right_elbow_pole": {"x": 0.2, "y": 0.0, "z": 0.0},
		"weapon_hand_position_correction": {"x": 0.04, "y": 0.0, "z": 0.0},
		"weapon_hand_rotation_correction_deg": {"x": 20.0, "y": -10.0, "z": 0.0},
	})
	blend_editor.set_time(0.5)
	var blended := blend_editor.sampled_pose()
	if (
		absf(float(blended["joint_rotations"]["spine2"]["x"]) - 5.0) > 0.001
		or absf(float(blended["weapon_hand_position_correction"]["x"]) - 0.02) > 0.001
		or absf(float(blended["weapon_hand_rotation_correction_deg"]["x"]) - 10.0) > 0.001
	):
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
	var reload_editor := FrameEditor.new()
	reload_editor.begin("reload_standing", &"reload", 3.3)
	reload_editor.set_time(1.0)
	var reload_pose := {
		"joint_rotations": {},
		"weapon_hand_position_correction": {"x": 0.02, "y": 0.0, "z": 0.0},
		"weapon_hand_rotation_correction_deg": {"x": 18.0, "y": -14.0, "z": 0.0},
	}
	reload_editor.store_current_pose(reload_pose)
	reload_editor.ensure_terminal_weapon_neutral_pose(reload_pose)
	reload_editor.set_time(3.3)
	var reload_terminal := reload_editor.current_pose()
	var terminal_rotation: Dictionary = reload_terminal.get(
		"weapon_hand_rotation_correction_deg", {}
	)
	var terminal_position: Dictionary = reload_terminal.get(
		"weapon_hand_position_correction", {}
	)
	if (
		absf(float(terminal_rotation.get("x", 1.0))) > 0.001
		or absf(float(terminal_rotation.get("y", 1.0))) > 0.001
		or absf(float(terminal_position.get("x", 1.0))) > 0.001
	):
		push_error("[GUNSMITH FRAME EDITOR] Reload weapon pitch/yaw did not return to neutral at the final frame.")
		quit(1)
		return
	var weapon_solver := WeaponPoseSolver.new()
	weapon_solver.set_animation_frame_pose({
		"weapon_hand_position_correction": {"x": 0.03, "y": -0.01, "z": 0.02},
		"weapon_hand_rotation_correction_deg": {"x": 12.0, "y": -8.0, "z": 3.0},
	})
	var weapon_correction := weapon_solver.call(
		"_animation_frame_weapon_correction_transform"
	) as Transform3D
	if (
		not weapon_correction.origin.is_equal_approx(Vector3(0.03, -0.01, 0.02))
		or rad_to_deg(weapon_correction.basis.get_rotation_quaternion().get_angle()) < 10.0
	):
		push_error("[GUNSMITH FRAME EDITOR] Gameplay did not consume the frame-local weapon correction.")
		weapon_solver.free()
		quit(1)
		return
	weapon_solver.free()
	print("[GUNSMITH FRAME EDITOR] PASS: correction keys persist, hold, and interpolate.")
	quit(0)
