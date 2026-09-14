extends "res://tools/main_source_motion_proof.gd"

const Graph := preload("res://scripts/player/operator_locomotion_blend_tree.gd")
var checks := 0
var candidate_installed := false
var observed_transfers := 0
var transfer_rows: Array[Dictionary] = []
var saved_policy_hash := ""
var saved_policy := false
var capture_phase_focus := false
var phase_stages: Dictionary = {}
var main_checks_completed := false

func _initialize() -> void:
	weapon_id = "m4a1"
	output_prefix = "/private/tmp/source-loop-phase-main"
	saved_policy_hash = FileAccess.get_sha256("res://config/source_animation_runtime.json")
	saved_policy = "--saved-policy" in OS.get_cmdline_user_args()
	capture_phase_focus = "--capture-phase-focus" in OS.get_cmdline_user_args()
	super._initialize()

func _request_shot() -> bool:
	return false

func _sample(state: String) -> void:
	if not candidate_installed:
		# Candidate built using the same owner/build API with one in-memory flag.
		# The saved production policy and original assets are not modified.
		if not saved_policy:
			driver.animation_tree.active = false
			driver.animation_tree.free()
			driver.locomotion_graph = Graph.new()
			driver.locomotion_graph.source_animation_runtime.settings.grounded_idle_phase_transfer_enabled = true
			driver.animation_tree = driver.locomotion_graph.build(driver, driver.animation_player, driver.available_clips, driver.animation_profile, driver.use_modern_locomotion, driver.equipped_weapon_handling_profile)
			driver.transition_node = driver.locomotion_graph.legacy_transition
		_check(driver.locomotion_graph.source_loop_phase_transfer.enabled, "selected canonical source phase policy active")
		driver.animation_tree.mixer_applied.connect(_observe_transfer)
		candidate_installed = true
		await _frames(25)
	var original_capture := capture
	if capture_phase_focus: capture = capture and state.begins_with("phase_")
	await super._sample(state)
	capture = original_capture

func _command(direction: Vector2) -> void:
	await super._command(direction)
	if not candidate_installed or not capture_phase_focus: return
	var graph: RefCounted = driver.locomotion_graph
	var helper: RefCounted = graph.source_loop_phase_transfer
	if helper.transfers != 1: return
	var row: Dictionary = helper.last_transfer
	if StringName(driver.animation_tree.get("parameters/modern_transition/current_state")) != row.to: return
	var states: Array[StringName] = [StringName(row.to)]
	var weight: float = graph.evaluated_modern_state_weight(states, driver.animation_tree.get_process_delta_time())
	var stage := "early" if weight < .1 else ("middle" if weight >= .35 and weight <= .7 else ("late" if weight >= .85 else ""))
	if stage != "" and not phase_stages.has(stage):
		phase_stages[stage] = true
		await _sample("phase_" + stage)
		if not samples.is_empty(): samples[-1]["phase_evaluated_target_weight"] = weight

func _observe_transfer() -> void:
	var helper: RefCounted = driver.locomotion_graph.source_loop_phase_transfer
	if helper.transfers == observed_transfers: return
	observed_transfers = helper.transfers
	var row: Dictionary = helper.last_transfer.duplicate(true)
	row["frame"] = Engine.get_process_frames()
	row["samples"] = []
	for entry: Dictionary in helper.destinations[row.to]:
		var actual := float(driver.animation_tree.get(entry.position)) / float(entry.period)
		_check(absf(actual - float(row.phase)) < .00001, "first actual destination evaluation inherits source phase")
		_check(float(driver.animation_tree.get(entry.seek)) == -1.0, "actual tree consumes each idle seek once")
		row.samples.append({"path":String(entry.position), "phase":actual})
	_check(driver.requested_action == &"" and player.is_on_floor(), "phase transfer remains grounded and action-free")
	transfer_rows.append(row)

func _extra_actions() -> void:
	var helper: RefCounted = driver.locomotion_graph.source_loop_phase_transfer
	_check(observed_transfers >= 6, "main actual standing/crouch directional stops transfer source phase")
	if capture_phase_focus: _check(phase_stages.size() == 3, "actual idle arrival early/middle/late captured")
	var stances := {}
	for row: Dictionary in transfer_rows: stances[row.to] = true
	_check(stances.has(&"idle") and stances.has(&"idle_crouch"), "standing and crouch destination coverage")
	var before: int = helper.transfers
	_check(super._request_shot(), "real shot accepted for excluded overlay proof")
	await _frames(2)
	_check(not driver.locomotion_graph._source_grounded_transition_safe(), "fire overlay excludes grounded transfer")
	_check(helper.transfers == before, "fire cannot cause source idle seek")
	_check(FileAccess.get_sha256("res://config/source_animation_runtime.json") == saved_policy_hash, "candidate never mutates saved policy")
	var file := FileAccess.open(output_prefix + "-phase.json", FileAccess.WRITE)
	_check(file != null, "main phase report writable")
	if file != null: file.store_string(JSON.stringify({"checks":checks, "transfers":observed_transfers, "failures":failures, "rows":transfer_rows}, "\t"))
	main_checks_completed = true
	print("SOURCE_LOOP_PHASE_MAIN ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " transfers=", observed_transfers, " ", failures)

func _finish() -> void:
	_check(main_checks_completed, "main phase regression completed without script interruption")
	super._finish()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok and not failures.has(label): failures.append(label)
