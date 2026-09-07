extends "res://tools/firearm_family_transition_regression.gd"

const Candidate := preload("res://tools/prone_authored_aim_candidate.gd")
var probe_done := false
var rows: Array[Dictionary] = []
var apply_candidate := false
var previous_sample: Dictionary = {}

func _initialize() -> void:
	super._initialize()
	apply_candidate = "--candidate" in OS.get_cmdline_user_args()
	if selected_ids.is_empty():
		selected_ids.assign(["m16a2"])
	if selected_ids.size()!=1:
		_fail_once("Prone candidate requires one weapon per process")

func _check_stance(_stance: int) -> void:
	if probe_done:
		return
	probe_done = true
	if not player.call("_try_set_posture",2):
		_fail_once("Prone posture refused")
	await _frames(120)
	for frame in 20:
		await _frames(1)
		_record_frame(frame-20)
	var result: Dictionary = controller.call("request_fire")
	if not bool(result.get("fired",false)):
		_fail_once("Prone shot refused")
	else:
		expected_accepted_shots += 1
	for frame in 180:
		await _frames(1)
		_record_frame(frame)
		if capture and frame in [0,8,35,70,90,119,140,179]:
			await _capture_state(weapon_id+"_prone_candidate_%03d"%frame)
	if not rows.any(func(row: Dictionary) -> bool: return row.frame>=0 and row.ready==0.0):
		_fail_once("Prone candidate never reached zero readiness after the shot")


func _record_frame(frame: int) -> void:
	var pose: Node3D = driver.get("weapon_pose_solver")
	var target: Vector3 = driver.get("last_world_aim_target") if "last_world_aim_target" in driver else pose.last_target_point
	var ready: float = driver.get("weapon_ready_weight")
	var latch: Dictionary = driver.call("get_animation_debug_state").get("fire_upper_body_latch",{})
	var aim_weight := 1.0 if bool(latch.get("selected",false)) else ready
	var applied := Candidate.apply(pose,target,ready,player,aim_weight) if apply_candidate else {}
	var physical := _measure_physical_pose()
	var row := {"frame":frame,"ready":ready,"aim_weight":aim_weight,"candidate":applied,"physical":physical,"left_elbow":_physical_elbow_angle(&"Left"),"right_elbow":_physical_elbow_angle(&"Right")}
	var sample := {}
	for side: String in ["Left","Right"]:
		var upper: Vector3 = pose._bone_world_position(StringName("mixamorig_%sArm"%side))
		var fore: Vector3 = pose._bone_world_position(StringName("mixamorig_%sForeArm"%side))
		var hand_index: int = pose.bone_indices.get(StringName("mixamorig_%sHand"%side),-1)
		var hand: Transform3D = pose.skeleton.global_transform*pose.skeleton.get_bone_global_pose(hand_index)
		sample[side] = {"relative_elbow":fore-upper,"wrist_basis":hand.basis.orthonormalized().get_rotation_quaternion()}
		if previous_sample.has(side):
			var step: float = (sample[side].relative_elbow as Vector3).distance_to(previous_sample[side].relative_elbow)
			var wrist_step: float = rad_to_deg((sample[side].wrist_basis as Quaternion).angle_to(previous_sample[side].wrist_basis))
			row[side.to_lower()+"_elbow_step_m"]=step
			row[side.to_lower()+"_wrist_step_deg"]=wrist_step
			if frame>0 and ready<0.01:
				if step>0.015 or wrist_step>5.0:
					_fail_once("Prone final readiness release pops elbow or wrist")
	previous_sample=sample
	rows.append(row)
	_assert_weapon_visible("prone frame%d"%frame)
	if apply_candidate:
		for side: String in ["left","right"]:
			var plane: Dictionary = applied[side+"_floor_plane"]
			if not bool(plane.feasible):
				_fail_once("Prone elbow plane cannot meet floor within20degree cap")
			if maxf(plane.shoulder_delta_m,plane.wrist_delta_m)>0.0001 or plane.segment_length_delta_m>0.0001:
				_fail_once("Prone elbow plane changes endpoint or bone length")
		if minf(applied.left_elbow_height,applied.right_elbow_height)<0.064:
			_fail_once("Prone elbow violates65mm floor clearance")
		if minf(applied.trigger_height,applied.support_height)<0.099:
			_fail_once("Prone palm violates100mm floor clearance")
		if applied.muzzle_height<0.084:
			_fail_once("Prone muzzle violates85mm floor clearance")
		if applied.floor_lift>pose.prone_maximum_floor_lift_m+0.000001:
			_fail_once("Prone rigid weapon floor lift exceeds existing cap")
	if aim_weight >= 0.98 and float(physical.bore_to_reticle_degrees)>1.0:
		_fail_once("Prone ready bore exceeds1degree")
	if maxf(float(physical.trigger_contact_m),float(physical.support_contact_m))>0.005:
		_fail_once("Prone palm gap exceeds5mm")
	for angle: float in [row.left_elbow,row.right_elbow]:
		if angle<42.0 or angle>150.0:
			_fail_once("Prone elbow outside42–150degrees")


func _runtime_source_signatures() -> Dictionary:
	var result := super._runtime_source_signatures()
	for path: String in ["res://tools/prone_authored_aim_candidate.gd","res://tools/prone_authored_aim_probe.gd"]:
		result[path]=FileAccess.get_sha256(path)
	return result

func _finish() -> void:
	var file := FileAccess.open(output_prefix+"-prone.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"candidate":apply_candidate,"rows":rows,"failures":failures,"sources_at_start":runtime_sources_at_start,"sources_at_finish":_runtime_source_signatures()},"\t"))
	super._finish()
