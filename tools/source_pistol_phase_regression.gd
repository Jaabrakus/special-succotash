extends "res://tools/main_source_motion_proof.gd"

## Canonical movement commands + accepted fire. No pose/clock overrides.
const STANDING: Array[StringName] = [&"walk_space", &"full_space", &"firing_walk_space", &"firing_run_space"]
const CROUCHED: Array[StringName] = [&"crouch_space", &"firing_crouch_space"]
var checks := 0
var checked_phase_frames := 0
var maximum_phase_gap := 0.0
var maximum_phase_step := 0.0
var previous: Dictionary = {}
var observed_tree: AnimationTree
var clock_checks := 0
var maximum_clock_error := 0.0
var accepted_shots := 0
var saw_ready := false
var focused_capture := false


func _initialize() -> void:
	weapon_id = "mark_23"
	output_prefix = "/private/tmp/source-pistol-phase"
	focused_capture = "--capture-pistol-focus" in OS.get_cmdline_user_args()
	super._initialize()


func _run() -> void:
	if capture and DisplayServer.get_name() == "headless":
		failures.append("--capture requires a display-backed run")
		_finish()
		return
	ProjectSettings.set_setting("socom/session/public_training", true)
	await super._run()


func _sample(state: String) -> void:
	var capture_requested := capture
	if focused_capture:
		# Twelve source samples, two views each: early/middle/late movement and
		# accepted-fire readiness for standing right + crouched forward.
		capture = capture_requested and ("_standing_move_right_" in state or "_crouched_move_forward_" in state)
	await super._sample(state)
	capture = capture_requested


func _request_shot() -> bool:
	var accepted := super._request_shot()
	if accepted: accepted_shots += 1
	return accepted


func _check_frame(label: String, _firing_sample: bool) -> void:
	var graph: RefCounted = driver.locomotion_graph
	var tree: AnimationTree = driver.animation_tree
	if observed_tree != tree:
		observed_tree = tree
		previous.clear()
		tree.mixer_applied.connect(_observe_evaluated_clock.bind(tree))
	_check(String(driver.equipped_weapon_config.weapon_id) == "mark_23", "actual pistol equipped")
	_check(graph.source_pistol_phase_active and not graph.source_controller_active, "phase sharing does not enable rifle tiers")
	_check(is_zero_approx(graph.jog_gait_weight), "no invented pistol jog band")
	var crouched: bool = driver.posture == &"CROUCHED"
	var spaces: Array[StringName] = CROUCHED if crouched else STANDING
	var group: StringName = &"crouched" if crouched else &"standing"
	_check(graph.gait_phase_sync.groups.has(group), "phase group exists")
	if not graph.gait_phase_sync.groups.has(group): return
	_check(graph.gait_phase_sync.groups[group].entries.size() == spaces.size(), "exact pistol sibling count")
	var reference := -1.0
	for space_name: StringName in spaces:
		var space := (tree.tree_root as AnimationNodeBlendTree).get_node(space_name) as AnimationNodeBlendSpace2D
		_check(space.sync_mode == AnimationNodeBlendSpace2D.SYNC_MODE_CYCLIC_CONSTANT, "shared constant mode")
		_check(absf(space.cyclic_length - float(graph.gait_phase_sync.groups[group].period)) < .000001, "one period")
		for point_index in space.get_blend_point_count():
			var point_name := space.get_blend_point_name(point_index)
			var point := space.get_blend_point_node(point_index) as AnimationNodeAnimation
			var length: float = driver.animation_player.get_animation(point.animation).length
			if point.use_custom_timeline:
				length = point.timeline_length
			var value: Variant = tree.get("parameters/%s/%s/current_position" % [space_name, point_name])
			_check((value is float or value is int) and is_finite(float(value)) and length > .0, "finite evaluated playhead")
			if not (value is float or value is int) or length <= 0.0: continue
			var phase := fposmod(float(value) / length, 1.0)
			if reference < 0.0: reference = phase
			var gap := absf(phase - reference)
			gap = minf(gap, 1.0 - gap)
			maximum_phase_gap = maxf(maximum_phase_gap, gap)
			_check(gap < .00001, "actual normalized sibling phase " + label)
	var measured := _measure_physical_pose()
	var trigger := float(measured.get("trigger_contact_m", INF))
	maximum_grip_error = maxf(maximum_grip_error, trigger)
	_check(is_finite(trigger) and trigger < .015, "pistol trigger contact")
	_check(player.is_on_floor(), "canonical body grounded")
	_check(Vector2(player.velocity.x, player.velocity.z).length() > .01, "real approach/movement rather than repositioned sample")
	saw_ready = saw_ready or driver.weapon_ready_weight > .95
	checked_phase_frames += 1


func _observe_evaluated_clock(tree: AnimationTree) -> void:
	if tree != driver.animation_tree or not driver.locomotion_graph.source_pistol_phase_active:
		return
	# This signal runs immediately after evaluation, before the driver's process
	# changes next-frame periods/rates. Long capture frames use their real delta.
	var state := StringName(tree.get("parameters/modern_transition/current_state"))
	for group: StringName in [&"standing", &"crouched"]:
		var active := state == (&"standing" if group == &"standing" else &"crouch")
		var space_name := &"walk_space" if group == &"standing" else &"crouch_space"
		var space := (tree.tree_root as AnimationNodeBlendTree).get_node(space_name) as AnimationNodeBlendSpace2D
		var point := space.get_blend_point_node(space.find_blend_point_by_name(&"forward")) as AnimationNodeAnimation
		var period := float(driver.locomotion_graph.gait_phase_sync.groups[group].period)
		var native: float = point.timeline_length if point.use_custom_timeline else driver.animation_player.get_animation(point.animation).length
		var phase := fposmod(float(tree.get("parameters/%s/forward/current_position" % space_name)) / native, 1.0)
		var rate := float(tree.get("parameters/%s_time_scale/scale" % ("standing" if group == &"standing" else "crouch")))
		if previous.has(group) and active and bool(previous[group].active):
			var expected := fposmod(float(previous[group].phase) + tree.get_process_delta_time() * rate / period, 1.0)
			var error := absf(phase - expected)
			error = minf(error, 1.0 - error)
			maximum_clock_error = maxf(maximum_clock_error, error)
			maximum_phase_step = maxf(maximum_phase_step, fposmod(phase - float(previous[group].phase), 1.0))
			_check(error < .00001, "evaluated delta/rate/period matches actual phase without resets")
			clock_checks += 1
		previous[group] = {"phase":phase, "active":active}


func _extra_actions() -> void:
	_check(accepted_shots == 6 and saw_ready, "real accepted shots exercised ready blend")
	_check(checked_phase_frames >= 400, "both stances/directions sampled")
	_check(clock_checks >= 350, "real evaluated clock checked across active movement frames")
	# Verify fallback independently without changing the live graph/settings.
	var graph_script := preload("res://scripts/player/operator_locomotion_blend_tree.gd")
	var profile_script := preload("res://scripts/player/operator_animation_profile.gd")
	var missing := graph_script.new()
	missing.profile = profile_script.new()
	missing.profile.load_project_map()
	missing.modern_enabled = true
	missing.weapon_handling_profile = {"family":"TWO_HAND_PISTOL"}
	missing.configure_source_phase_sync(AnimationNodeBlendTree.new())
	_check(not missing.source_pistol_phase_active and missing.gait_phase_sync.groups.is_empty(), "missing cardinal graph fails closed")
	var live_root := driver.animation_tree.tree_root as AnimationNodeBlendTree
	missing.modern_enabled = false
	missing.configure_source_phase_sync(live_root)
	_check(not missing.source_pistol_phase_active and missing.gait_phase_sync.groups.is_empty(), "disabled modern policy cannot change graph")
	missing.modern_enabled = true
	missing.profile.locomotion["preserve_source_locomotion"] = false
	missing.configure_source_phase_sync(live_root)
	_check(not missing.source_pistol_phase_active and missing.gait_phase_sync.groups.is_empty(), "disabled source policy retains fallback")
	missing.profile.locomotion["preserve_source_locomotion"] = true
	var source_space := live_root.get_node(&"walk_space") as AnimationNodeBlendSpace2D
	var source_point := source_space.get_blend_point_node(source_space.find_blend_point_by_name(&"forward")) as AnimationNodeAnimation
	# Separate unsaved profile: never mutate the running driver's map or nodes.
	missing.profile.clip_paths[source_point.animation] = "res://non_source_fixture.tres"
	missing.configure_source_phase_sync(live_root)
	_check(not missing.source_pistol_phase_active and missing.gait_phase_sync.groups.is_empty(), "mixed non-source cardinal graph fails closed before binding")
	# Real equip rebuild: established rifle six-space policy must still apply.
	feeder.direction = Vector2.ZERO
	_check(controller.apply_authorized_weapon_pickup("res://config/weapons/m4a1.json"), "canonical rifle re-equip")
	await _frames(35)
	var rifle: RefCounted = driver.locomotion_graph
	_check(rifle.source_controller_active and not rifle.source_pistol_phase_active, "rifle policy unchanged")
	_check(rifle.gait_phase_sync.groups[&"standing"].entries.size() == 6, "rifle six source branches retained")
	print("SOURCE_PISTOL_PHASE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " frames=", checked_phase_frames, " phase_gap=", maximum_phase_gap, " maximum_step=", maximum_phase_step, " clock_checks=", clock_checks, " clock_error=", maximum_clock_error, " trigger_m=", maximum_grip_error)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok and not failures.has(label):
		failures.append(label)
		push_error("SOURCE_PISTOL_PHASE " + label)
