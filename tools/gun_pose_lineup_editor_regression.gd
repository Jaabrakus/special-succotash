extends SceneTree

const LINEUP_SCENE := preload("res://scenes/labs/gun_pose_lineup_lab.tscn")
const EXPECTED := {
	"00_IdleRifle": ["idle_rifle", "idle_rifle"],
	"01_AimIdle": ["aim_idle", "aim_idle"],
	"02_CombatReady": ["combat_ready", "aim_idle"],
	"03_CombatFire": ["combat_fire", "combat_fire"],
	"04_RunForward": ["run_forward", "run_forward"],
	"05_RunLeft": ["run_left", "run_left"],
	"06_RunRight": ["run_right", "run_right"],
	"07_CrouchMove": ["crouch_move", "crouch_forward"],
	"08_ProneMove": ["prone_move", "prone_forward"],
	"09_Reload": ["reload", "reload"],
}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var lab := LINEUP_SCENE.instantiate()
	root.add_child(lab)
	await process_frame
	await process_frame
	var failures: Array[String] = []
	var lineup := lab.get_node_or_null("PoseLineup")
	_check(lineup != null, "PoseLineup exists", failures)
	if lineup != null:
		_check(lineup.get_child_count() == EXPECTED.size(), "ten contexts exist", failures)
		var last_x := -INF
		for pose_name: String in EXPECTED:
			var pose := lineup.get_node_or_null(pose_name) as Node3D
			_check(pose != null, "%s exists" % pose_name, failures)
			if pose == null:
				continue
			_check(pose.position.x > last_x, "%s is ordered horizontally" % pose_name, failures)
			last_x = pose.position.x
			_check(String(pose.get_meta("context", "")) == EXPECTED[pose_name][0], "%s context" % pose_name, failures)
			_check(String(pose.get_meta("clip_key", "")) == EXPECTED[pose_name][1], "%s clip" % pose_name, failures)
			var skeleton_found := (
				pose.get_node_or_null("OperatorRig/VisualModel/Skeleton3D") != null
				or pose.get_node_or_null("OperatorRig/VisualModel/Model/GeneralSkeleton") != null
				or pose.find_child("*Skeleton*", true, false) != null
			)
			_check(skeleton_found, "%s has canonical Skeleton3D" % pose_name, failures)
			for required_path in [
				"OperatorRig/IKControlGraph/TargetPivot/RHUpperArmWeaponTarget",
				"OperatorRig/IKControlGraph/TargetPivot/RHWeaponTarget",
				"OperatorRig/IKControlGraph/TargetPivot/LHWeaponContactTarget",
				"OperatorRig/IKControlGraph/TargetPivot/SpineTargetWeaponAim",
				"AnimationPlayer",
				"EditorWeapon",
			]:
				_check(pose.get_node_or_null(required_path) != null, "%s has %s" % [pose_name, required_path], failures)
	var snapshot: Dictionary = lab.call("get_debug_snapshot")
	_check(bool(snapshot.get("initialized", false)), "tool initialized every animation", failures)
	_check(int(snapshot.get("pose_count", 0)) == EXPECTED.size(), "debug snapshot reports ten poses", failures)
	_check(bool(snapshot.get("native_scene_tree", false)), "native Scene tree contract", failures)
	_check(not bool(snapshot.get("gameplay_scene_changed", true)), "editor lab is isolated from gameplay", failures)
	if failures.is_empty():
		print("GUN_POSE_LINEUP_EDITOR_REGRESSION PASS poses=10 native_hierarchy=true")
		quit(0)
	else:
		for failure: String in failures:
			push_error("GUN_POSE_LINEUP_EDITOR_REGRESSION FAIL: %s" % failure)
		quit(1)


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
