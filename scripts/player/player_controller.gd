class_name SocomTestPlayer
extends CharacterBody3D

signal mobility_action_started(state_name: StringName)
signal mobility_action_requested(state_name: StringName)

const OperatorOrientationController := preload("res://scripts/player/operator_orientation_controller.gd")
const MovementCommand := preload("res://scripts/network/socom_movement_command.gd")
const TraversalRuntime := preload("res://scripts/traversal/socom_traversal_runtime.gd")
const JumpComboIntent := preload("res://scripts/player/jump_direction_combo_intent.gd")
const LeanLatch := preload("res://scripts/player/player_lean_latch.gd")
const StepProbe := preload("res://scripts/player/player_step_probe.gd")

@export var move_speed: float = 6.5
@export var strafe_speed: float = 6.5
@export var instant_strafe_response: bool = true
@export var acceleration: float = 45.0
@export var braking_acceleration: float = 60.0
@export var reversal_acceleration: float = 90.0
@export var turn_response: float = 12.0
@export var gravity: float = 22.0
@export_range(1.0, 1000.0, 1.0) var max_health: float = 100.0
var current_health: float = 100.0

@export_group("Competitive strafe")
@export_range(1, 4, 1) var strafe_burst_frames: int = 2
@export_range(1.0, 1.5, 0.01) var strafe_burst_multiplier: float = 1.18
@export_range(0.0, 0.40, 0.01) var strafe_burst_decay_seconds: float = 0.12
@export_range(0.20, 1.50, 0.05) var strafe_chain_window_seconds: float = 0.70

@export_group("Locomotion orientation")
@export_range(1.0, 30.0, 0.5) var idle_turn_response: float = 9.0
@export_range(0.0, 10.0, 0.1) var torso_turn_in_place_limit_deg: float = 0.5
@export_range(0.0, 0.90, 0.01) var torso_catchup_release_ratio: float = 0.0
@export_range(0.25, 0.95, 0.01) var full_gait_input_threshold: float = 0.72

@export_group("Tactical mobility")
@export var crouch_speed: float = 2.6
@export var prone_speed: float = 1.25
# Tuned for the SOCOM-scale tactical hop. At gravity 22 this peaks around
# 0.55-0.60 m; the previous 6.2 m/s impulse could lift the full standing
# capsule roughly 1.75 m and visibly drive the operator through low ceilings.
@export var jump_velocity: float = 5.0
var active_jump_launch_speed: float = 5.0
@export var dive_speed: float = 7.6
@export var dive_duration: float = 0.78
@export var dive_minimum_run_speed: float = 2.8
@export var roll_speed: float = 6.8
@export var roll_duration: float = 0.62
@export var landing_recovery: float = 0.18
@export_range(1.0, 30.0, 0.5) var peek_enter_response: float = 13.0
@export_range(1.0, 30.0, 0.5) var peek_exit_response: float = 16.0

@export_group("Automatic traversal")
@export var automatic_vault_enabled: bool = true
@export_range(0.02, 0.25, 0.01) var automatic_vault_probe_interval: float = 0.08
@export_range(0.05, 1.00, 0.05) var automatic_vault_retry_seconds: float = 0.45
@export_range(0.0, 6.5, 0.1) var automatic_vault_minimum_speed: float = 2.2

enum MotionState {
	STANDING,
	CROUCHED,
	PRONE,
	AIRBORNE,
	LANDING,
	DIVING,
	ROLLING,
	VAULTING,
}

var movement_yaw: float = 0.0
var replay_override_active: bool = false
var posture: int = MotionState.STANDING
var motion_state: int = MotionState.STANDING
var action_elapsed: float = 0.0
var action_duration: float = 0.0
var action_direction: Vector3 = Vector3.FORWARD
var roll_side: float = 1.0
var was_on_floor: bool = true
var orientation := OperatorOrientationController.new()
var desired_movement_direction := Vector3.ZERO
var movement_input_strength: float = 0.0
var horizontal_response_mode: StringName = &"IDLE"
var movement_command_queue: Array = []
var last_movement_command
var local_input_enabled: bool = true

# Context-Sensitive Multi-Function Input
var stance_hold_timer: float = 0.0
var stance_held_triggered: bool = false
var stance_hold_threshold: float = 0.20
var jump_was_held: bool = false
var jump_requested: bool = false
var peek_amount: float = 0.0
var lean_latch := LeanLatch.new()
var _strafe_burst_frames_remaining: int = 0
var _strafe_burst_decay_remaining: float = 0.0
var _last_lateral_input_sign: int = 0
var _seconds_since_strafe_reversal: float = INF
var _last_lateral_input_action: StringName = &""
var _left_input_was_held: bool = false
var _right_input_was_held: bool = false
var traversal := TraversalRuntime.new()
var automatic_vault_probe_remaining: float = 0.0
var automatic_vault_retry_remaining: float = 0.0
var jump_combo_intent := JumpComboIntent.new()
var mobility_combo_kind: StringName = &""
var pending_jump_slide: bool = false
var combo_direction := Vector3.FORWARD
var combo_wall_blocked: bool = false
var combo_recovering: bool = false
var combo_rest_input_released: bool = false
var combo_exit_prone: bool = false


func _input(event: InputEvent) -> void:
	if not local_input_enabled:
		return
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	# Preserve the order of opposing lateral presses. Input.get_vector()
	# normally cancels A + D to zero, but tactical movement expects the newest
	# direction to take control while both buttons remain held.
	if event.is_action_pressed(&"move_left"):
		_last_lateral_input_action = &"move_left"
	if event.is_action_pressed(&"move_right"):
		_last_lateral_input_action = &"move_right"


func configure_max_health(value: float, refill: bool = true) -> void:
	var previous_max := maxf(max_health, 1.0)
	var previous_ratio := clampf(current_health / previous_max, 0.0, 1.0)
	max_health = clampf(value, 1.0, 1000.0)
	current_health = max_health if refill else max_health * previous_ratio


func set_current_health(value: float) -> void:
	current_health = clampf(value, 0.0, max_health)


func apply_damage(value: float) -> float:
	var previous := current_health
	set_current_health(current_health - maxf(value, 0.0))
	return previous - current_health

func is_dead_for_presentation() -> bool:
	return current_health <= 0.0


func is_fire_locked_by_mobility() -> bool:
	# Slides and every dive variant share the committed DIVING state. The
	# CharacterBody owns that state; weapon systems only consume this decision.
	return motion_state == MotionState.DIVING or traversal.is_hanging() or traversal.is_on_ladder() or traversal.is_narrow_walking() or (traversal.is_mantling() and StringName(traversal.state_machine.context.get("action_type", &"")) == &"climb")


func take_explosion_damage(
	damage: float,
	_explosion_origin: Vector3,
	_attacker_peer_id: int = 0
) -> Dictionary:
	var applied := apply_damage(damage)
	return {
		"accepted": applied > 0.0,
		"damage": applied,
		"remaining_health": current_health,
		"eliminated": current_health <= 0.0,
	}

func _physics_process(delta: float) -> void:
	if is_dead_for_presentation():
		lean_latch.reset()
		peek_amount = 0.0
		reset_jump_combos()
		movement_command_queue.clear()
		jump_requested = false
		stance_hold_timer = 0.0
		stance_held_triggered = false
		velocity = Vector3.ZERO
		return
	if replay_override_active:
		return
	var command = _consume_movement_command()
	last_movement_command = command.duplicate_command()
	var input: Vector2 = command.move_axis
	var automated_world_direction: Vector3 = command.world_move_override
	var authoritative_aim_yaw: float = command.aim_yaw
	var peek_eligible: bool = (
		motion_state in [MotionState.STANDING, MotionState.CROUCHED, MotionState.PRONE, MotionState.LANDING]
		and not traversal.is_swimming() and not traversal.is_mantling()
		and not command.jump_pressed and not jump_requested and not command.dive_pressed
	)
	var was_leaning: bool = lean_latch.is_active()
	var peek_target: float = lean_latch.update(command, peek_eligible, delta)
	if lean_latch.is_active() and not was_leaning:
		reset_jump_combos()
	if OS.get_cmdline_user_args().has("--peek-left-test"):
		peek_target = -1.0
	elif OS.get_cmdline_user_args().has("--peek-right-test"):
		peek_target = 1.0
	if motion_state in [MotionState.DIVING, MotionState.ROLLING, MotionState.AIRBORNE]:
		peek_target = 0.0
	var peek_response := peek_enter_response if absf(peek_target) > absf(peek_amount) else peek_exit_response
	peek_amount = move_toward(peek_amount, peek_target, peek_response * delta)
	_apply_posture_collider()
	if OS.get_cmdline_user_args().has("--movement-test"):
		input = Vector2(1.0, 0.0)
	elif OS.get_cmdline_user_args().has("--prone-forward-test"):
		input = Vector2(0.0, -1.0)
	elif OS.get_cmdline_user_args().has("--wall-entry-test"):
		input = Vector2.ZERO
		var test_frame := Engine.get_physics_frames()
		if test_frame < 150:
			automated_world_direction = Vector3.LEFT
		elif test_frame >= 420 and test_frame < 540:
			automated_world_direction = Vector3.RIGHT
	elif OS.get_cmdline_user_args().has("--wall-follow-test"):
		input = Vector2.ZERO
		var follow_frame := Engine.get_physics_frames()
		if follow_frame < 600:
			automated_world_direction = Vector3.RIGHT
	elif OS.get_cmdline_user_args().has("--camera-stress-test"):
		input = Vector2.ZERO
		var stress_phase: int = Engine.get_physics_frames() % 600
		if stress_phase < 150:
			automated_world_direction = Vector3.LEFT
		elif stress_phase < 300:
			automated_world_direction = Vector3.FORWARD
		elif stress_phase < 450:
			automated_world_direction = Vector3.RIGHT
		else:
			automated_world_direction = Vector3.BACK
	elif OS.get_cmdline_user_args().has("--automated-test"):
		input = Vector2.ZERO
	if lean_latch.is_active() and not lean_latch.previous_axis_active:
		# Ignore stick noise while planted; taps otherwise enter the same solver.
		input = Vector2.ZERO
		automated_world_direction = Vector3.ZERO
	# Travel follows raw aim authority, never the rendered camera transform.
	# A wall post-solve can move the lens without bending WASD travel.
	var aim_basis := Basis(Vector3.UP, authoritative_aim_yaw)
	var forward: Vector3 = aim_basis * Vector3.FORWARD
	var right: Vector3 = aim_basis * Vector3.RIGHT

	var desired_dir := (right * input.x + forward * -input.y)
	if automated_world_direction != Vector3.ZERO:
		desired_dir = automated_world_direction
	if desired_dir.length_squared() > 1.0:
		desired_dir = desired_dir.normalized()
	desired_movement_direction = desired_dir
	movement_input_strength = clampf(desired_dir.length(), 0.0, 1.0)

	if traversal.is_swimming():
		reset_jump_combos()
		var vertical_axis := (
			1.0 if command.jump_held
			else (-1.0 if command.crouch_held else 0.0)
		)
		var swimming_solution := traversal.solve_swimming(
			velocity,
			desired_dir,
			vertical_axis,
			global_position.y,
			delta
		)
		velocity = swimming_solution.get("velocity", velocity) as Vector3
		horizontal_response_mode = &"SWIMMING"
		_update_orientation(desired_dir, authoritative_aim_yaw, delta)
		_move_body_with_collision()
		was_on_floor = _movement_floor_contact()
		return

	var actions_enabled := not (
		OS.get_cmdline_user_args().has("--automated-test")
		or OS.get_cmdline_user_args().has("--movement-test")
		or OS.get_cmdline_user_args().has("--wall-entry-test")
		or OS.get_cmdline_user_args().has("--wall-follow-test")
		or OS.get_cmdline_user_args().has("--camera-stress-test")
	)
	automatic_vault_probe_remaining = maxf(
		automatic_vault_probe_remaining - delta,
		0.0
	)
	automatic_vault_retry_remaining = maxf(
		automatic_vault_retry_remaining - delta,
		0.0
	)
	var jump_started: bool = jump_requested or command.jump_pressed
	jump_requested = false
	if traversal.is_narrow_walking():
		reset_jump_combos()
		if jump_started:
			# A deliberate jump returns to the existing jump/airborne path below.
			traversal.leave_grip()
			motion_state = posture
			automatic_vault_retry_remaining = 0.45
		else:
			var before := global_position
			var narrow_solution := traversal.solve_narrow(self, desired_dir, delta)
			velocity = narrow_solution.get("velocity", Vector3.ZERO)
			horizontal_response_mode = &"NARROW_LEDGE"
			_update_orientation(desired_dir, authoritative_aim_yaw, delta)
			_move_body_with_collision()
			if traversal.is_narrow_walking():
				var narrow_context := traversal.state_machine.context
				var travelled := (global_position - before).dot(Vector3(narrow_context.travel_axis))
				narrow_context["travel_metres"] = float(narrow_context.get("travel_metres", 0.0)) + absf(travelled)
				narrow_context["travel_sign"] = signf(travelled) if absf(travelled) > 0.00001 else 0.0
			else:
				motion_state = posture if _movement_floor_contact() else MotionState.AIRBORNE
			was_on_floor = _movement_floor_contact()
			return
	if traversal.is_hanging() or traversal.is_on_ladder():
		reset_jump_combos()
		var hanging := traversal.is_hanging()
		if hanging and input.y >= -0.2:
			traversal.state_machine.context["forward_released"] = true
		var forward_climb := hanging and input.y < -0.2 and bool(traversal.state_machine.context.get("forward_released", false))
		var ladder_input := traversal.ladder_jump_input(jump_started, command.jump_held, delta) if traversal.is_on_ladder() else {"detach": false, "slide": false}
		if command.crouch_held or (hanging and input.y > 0.2) or bool(ladder_input.detach):
			traversal.leave_grip()
			motion_state = MotionState.AIRBORNE
			velocity = Vector3.ZERO
			automatic_vault_retry_remaining = 0.75
		elif (forward_climb or (jump_started and input.y < -0.2)) and traversal.pull_up(self):
			_advance_automatic_vault(authoritative_aim_yaw, delta)
			return
		else:
			if hanging:
				traversal.shimmy(self, input.x, delta)
			var grip_axis := 0.0 if traversal.is_on_ladder() and bool(traversal.state_machine.context.get("jump_tracking", false)) else -input.y
			velocity = traversal.solve_grip(self, grip_axis, delta, bool(ladder_input.slide)).velocity
			horizontal_response_mode = &"VAULTING"
			_move_body_with_collision()
			if not traversal.is_active():
				motion_state = MotionState.AIRBORNE
				automatic_vault_retry_remaining = 0.45
			was_on_floor = _movement_floor_contact()
			return
	if actions_enabled and jump_started and posture == MotionState.STANDING and motion_state in [MotionState.STANDING, MotionState.LANDING, MotionState.AIRBORNE] and automatic_vault_retry_remaining <= 0.0 and not lean_latch.is_active() and traversal.try_enter_ladder(self, desired_dir):
		reset_jump_combos()
		motion_state = MotionState.VAULTING
		velocity = Vector3.ZERO
		return
	# Reload is a filtered upper-body action. Jump remains an immediate
	# CharacterBody3D movement decision and continues under the same reload
	# playhead; it must not cancel reload or queue a delayed jump.
	if traversal.is_mantling():
		reset_jump_combos()
		_advance_automatic_vault(authoritative_aim_yaw, delta)
		return
	# A fresh tap or held Jump catches a ledge; fresh forward pulls up afterward.
	# Releasing movement must not discard a tap or held airborne grab ahead.
	# A rejected probe falls through to the ordinary jump/gravity path.
	var climb_requested: bool = jump_started or (command.jump_held and motion_state == MotionState.AIRBORNE)
	var climb_direction := desired_dir
	if climb_requested and climb_direction.length_squared() < 0.01:
		climb_direction = Vector3.FORWARD.rotated(Vector3.UP, authoritative_aim_yaw)
	if actions_enabled and not lean_latch.is_active() and mobility_combo_kind == &"" and climb_requested and _try_begin_automatic_vault(climb_direction, true, jump_started):
		reset_jump_combos()
		_advance_automatic_vault(authoritative_aim_yaw, delta)
		return
	if (
		actions_enabled
		and not jump_started
		and not lean_latch.is_active()
		and mobility_combo_kind == &"" and not pending_jump_slide and not jump_combo_intent.armed
		and _try_begin_automatic_vault(desired_dir)
	):
		_advance_automatic_vault(authoritative_aim_yaw, delta)
		return
	var launched_jump_this_frame := false
	if actions_enabled:
		_handle_posture_command(command, delta, desired_dir)
		launched_jump_this_frame = _try_begin_mobility_action(
			desired_dir,
			input,
			jump_started,
			command
		)
		if not lean_latch.is_active():
			_update_jump_combo(command, launched_jump_this_frame, delta)

	if motion_state == MotionState.DIVING or motion_state == MotionState.ROLLING:
		_advance_committed_action(delta)
		if motion_state == MotionState.DIVING or motion_state == MotionState.ROLLING:
			_update_orientation(action_direction, authoritative_aim_yaw, delta)
			_move_body_with_collision()
			_finish_committed_action_on_collision()
			was_on_floor = _movement_floor_contact()
			return
		# Completion consumes this tick's held movement below, with one collision move.

	var competitive_strafe_scale := _update_competitive_strafe(input, delta)
	var speed := (
		_directional_movement_speed(input, _movement_speed())
		* competitive_strafe_scale
	)
	var desired_velocity := desired_dir * speed
	if lean_latch.is_active():
		# Absolute speed cap: diagonal travel and strafe boosts cannot amplify
		# a peek step. Gravity and collision still use the normal body path.
		desired_velocity = desired_dir * minf(speed, lean_latch.peek_speed())
	# Accelerate as one horizontal vector. Advancing X and Z separately makes
	# diagonal response up to sqrt(2) times stronger than cardinal response.
	var horizontal_velocity := Vector2(velocity.x, velocity.z)
	var horizontal_target := Vector2(desired_velocity.x, desired_velocity.z)
	if not _movement_floor_contact():
		horizontal_response_mode = &"AIRBORNE"
		horizontal_velocity = horizontal_velocity.move_toward(
			horizontal_target,
			5.0 * delta
		)
	elif lean_latch.is_active():
		horizontal_response_mode = &"LEAN_PEEK"
		horizontal_velocity = horizontal_target
	elif posture == MotionState.CROUCHED and _movement_floor_contact() and bool(jump_combo_intent.profile.get("instant_crouch_response", false)):
		horizontal_response_mode = &"INSTANT_CROUCH"
		horizontal_velocity = horizontal_target
	elif instant_strafe_response and absf(input.x) > 0.001:
		horizontal_response_mode = &"INSTANT_STRAFE"
		horizontal_velocity = horizontal_target
	else:
		var response_acceleration := _horizontal_response_acceleration(
			horizontal_velocity,
			horizontal_target
		)
		horizontal_velocity = horizontal_velocity.move_toward(
			horizontal_target,
			response_acceleration * delta
		)
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.y

	if launched_jump_this_frame:
		# Preserve the impulse assigned above. _movement_floor_contact() remains true until
		# _move_body_with_collision(), so the normal grounded branch must not erase it.
		pass
	elif not _movement_floor_contact():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.5

	_update_orientation(desired_dir, authoritative_aim_yaw, delta)

	_move_body_with_collision(delta)
	_update_air_and_landing_state(delta)
	was_on_floor = _movement_floor_contact()

func _update_orientation(
	desired_dir: Vector3,
	authoritative_aim_yaw: float,
	delta: float
) -> void:
	orientation.update(
		self,
		desired_dir,
		authoritative_aim_yaw,
		delta,
		turn_response,
		idle_turn_response,
		deg_to_rad(torso_turn_in_place_limit_deg),
		torso_catchup_release_ratio
	)
	movement_yaw = rotation.y

func get_aim_relative_yaw() -> float:
	return orientation.aim_relative_yaw

func _directional_movement_speed(move_axis: Vector2, forward_speed: float) -> float:
	if move_axis.length_squared() < 0.000001:
		return forward_speed
	var standing_ratio := clampf(strafe_speed / maxf(move_speed, 0.001), 0.10, 2.0)
	var lateral_weight := absf(move_axis.x) / maxf(move_axis.length(), 0.001)
	return lerpf(forward_speed, forward_speed * standing_ratio, lateral_weight)


func _update_competitive_strafe(move_axis: Vector2, delta: float) -> float:
	# Every simulation owns the same deterministic two-frame burst.
	# Clients can submit only a bounded axis, so they cannot request a faster
	# burst. Holding one direction always settles at the authored base speed.
	_seconds_since_strafe_reversal += maxf(delta, 0.0)
	var lateral_sign := int(signf(move_axis.x)) if absf(move_axis.x) > 0.05 else 0
	if posture != MotionState.STANDING or lateral_sign == 0:
		_strafe_burst_frames_remaining = 0
		_strafe_burst_decay_remaining = 0.0
		if _seconds_since_strafe_reversal > strafe_chain_window_seconds:
			_last_lateral_input_sign = 0
		return 1.0

	var starting_strafe := _last_lateral_input_sign == 0
	var reversing := (
		_last_lateral_input_sign != 0
		and lateral_sign != _last_lateral_input_sign
	)
	if starting_strafe:
		_strafe_burst_frames_remaining = strafe_burst_frames
		_strafe_burst_decay_remaining = strafe_burst_decay_seconds
	elif reversing:
		_seconds_since_strafe_reversal = 0.0
		_strafe_burst_frames_remaining = strafe_burst_frames
		_strafe_burst_decay_remaining = strafe_burst_decay_seconds
	_last_lateral_input_sign = lateral_sign

	if _strafe_burst_frames_remaining <= 0:
		if _strafe_burst_decay_remaining <= 0.0:
			return 1.0
		_strafe_burst_decay_remaining = maxf(
			0.0,
			_strafe_burst_decay_remaining - maxf(delta, 0.0)
		)
		var decay_ratio := clampf(
			_strafe_burst_decay_remaining / maxf(strafe_burst_decay_seconds, 0.001),
			0.0,
			1.0
		)
		return lerpf(1.0, strafe_burst_multiplier, smoothstep(0.0, 1.0, decay_ratio))
	_strafe_burst_frames_remaining -= 1
	return strafe_burst_multiplier

func get_desired_movement_direction() -> Vector3:
	return desired_movement_direction

func get_peek_amount() -> float:
	return peek_amount

func is_turning_in_place() -> bool:
	return orientation.is_turning_in_place

func request_jump() -> void:
	# Public one-shot command used by replay/network input snapshots and tests.
	# Local keyboard/controller input still enters through the same latch above.
	jump_requested = true

func queue_movement_command(command) -> void:
	# Network/replay code may enqueue immutable per-tick commands. The queue is
	# deliberately independent from camera nodes and local device state.
	if command != null:
		movement_command_queue.push_back(command.duplicate_command())

func set_local_input_enabled(enabled: bool) -> void:
	local_input_enabled = enabled
	if not enabled:
		lean_latch.reset()
		peek_amount = 0.0
		jump_combo_intent.reset()
		pending_jump_slide = false

func get_last_movement_command():
	return last_movement_command.duplicate_command() if last_movement_command != null else null

func _consume_movement_command():
	if not movement_command_queue.is_empty():
		return movement_command_queue.pop_front()
	return _capture_local_movement_command()

func _capture_local_movement_command():
	var command = MovementCommand.new()
	command.simulation_tick = Engine.get_physics_frames()
	command.aim_yaw = global_rotation.y
	var rig := get_tree().get_first_node_in_group("socom_camera_rig")
	if rig != null:
		command.aim_yaw = float(rig.get("aim_yaw"))
		command.aim_pitch = float(rig.get("aim_pitch"))
	if not local_input_enabled:
		return command
	var raw_move_axis := Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)
	command.move_axis = _resolve_opposing_lateral_input(raw_move_axis)
	command.jump_pressed = Input.is_action_just_pressed("jump")
	command.jump_held = Input.is_action_pressed("jump")
	for entry in [["move_forward", 1], ["move_left", 2], ["move_right", 4], ["move_back", 8]]:
		if Input.is_action_pressed(entry[0]):
			command.direction_held_mask |= int(entry[1])
	command.dive_pressed = Input.is_action_just_pressed("dive")
	command.crouch_held = Input.is_action_pressed("crouch")
	command.crouch_released = Input.is_action_just_released("crouch")
	command.peek_axis = Input.get_axis("peek_left", "peek_right")
	command.peek_held_mask = (1 if Input.is_action_pressed("peek_left") else 0) | (2 if Input.is_action_pressed("peek_right") else 0)
	return command


func _resolve_opposing_lateral_input(raw_move_axis: Vector2) -> Vector2:
	var left_held := Input.is_action_pressed(&"move_left")
	var right_held := Input.is_action_pressed(&"move_right")
	var left_became_held := left_held and not _left_input_was_held
	var right_became_held := right_held and not _right_input_was_held

	# Input.action_press() does not emit an InputEvent. This fallback keeps
	# automated tests and replay harnesses consistent with physical input.
	if left_became_held != right_became_held:
		_last_lateral_input_action = (
			&"move_left" if left_became_held else &"move_right"
		)
	_left_input_was_held = left_held
	_right_input_was_held = right_held

	if left_held and right_held:
		if _last_lateral_input_action == &"move_left":
			raw_move_axis.x = -Input.get_action_strength(&"move_left")
		else:
			_last_lateral_input_action = &"move_right"
			raw_move_axis.x = Input.get_action_strength(&"move_right")
	elif left_held:
		_last_lateral_input_action = &"move_left"
		raw_move_axis.x = -Input.get_action_strength(&"move_left")
	elif right_held:
		_last_lateral_input_action = &"move_right"
		raw_move_axis.x = Input.get_action_strength(&"move_right")
	else:
		_last_lateral_input_action = &""
		raw_move_axis.x = 0.0
	return raw_move_axis.limit_length(1.0)

func _movement_speed() -> float:
	if motion_state == MotionState.LANDING:
		return move_speed * 0.60
	if posture == MotionState.PRONE:
		return prone_speed
	if posture == MotionState.CROUCHED:
		return crouch_speed
	return move_speed

func _horizontal_response_acceleration(current: Vector2, target: Vector2) -> float:
	if target.length_squared() < 0.0001:
		horizontal_response_mode = &"BRAKING" if current.length_squared() > 0.0001 else &"IDLE"
		return braking_acceleration
	if current.length_squared() > 0.0001:
		var alignment := current.normalized().dot(target.normalized())
		if alignment < -0.20:
			horizontal_response_mode = &"REVERSING"
			return reversal_acceleration
		if horizontal_response_mode == &"REVERSING":
			# Keep the reversal response active after velocity crosses zero.
			# Without this latch, the second half falls back to ordinary
			# acceleration and makes a left-right duel feel soft and delayed.
			var reached_new_direction := (
				alignment >= 0.95
				and current.length() >= target.length() * 0.95
			)
			if not reached_new_direction:
				return reversal_acceleration
	elif horizontal_response_mode == &"REVERSING":
		# An exact zero is the midpoint of a reversal, not the end of it.
		return reversal_acceleration
	horizontal_response_mode = &"ACCELERATING"
	return acceleration

func get_horizontal_response_mode() -> StringName:
	return horizontal_response_mode

func get_movement_gait_name() -> StringName:
	# SOCOM has no sprint command. The locomotion gait follows analog stick
	# magnitude: a partial stick walks and a full stick uses the quick tactical
	# gait. Keyboard WASD naturally reports full magnitude.
	return (
		&"FULL"
		if posture == MotionState.STANDING
		and movement_input_strength >= full_gait_input_threshold
		else &"WALK"
	)


func enter_swimming(water_surface_y: float, source_id: StringName = &"water") -> Dictionary:
	var result := traversal.enter_swimming(water_surface_y, source_id)
	if bool(result.get("accepted", false)):
		posture = MotionState.STANDING
		motion_state = MotionState.STANDING
		action_elapsed = 0.0
		action_duration = 0.0
		_apply_posture_collider()
	return result


func leave_swimming(source_id: StringName = &"water") -> Dictionary:
	return traversal.leave_swimming(source_id)


func get_traversal_mode_name() -> StringName:
	return traversal.state_machine.current_mode


func get_traversal_snapshot() -> Dictionary:
	return traversal.snapshot()


func get_traversal_presentation() -> Dictionary:
	var context: Dictionary = traversal.state_machine.context
	var slot := ""
	if traversal.is_hanging(): slot = "hang_free" if context.get("hang_style","braced") == "free" else "hang"
	elif traversal.is_narrow_walking():
		var travel_sign := float(context.get("travel_sign", 0.0))
		slot = "narrow_idle" if is_zero_approx(travel_sign) else ("narrow_right" if travel_sign > 0.0 else "narrow_left")
	elif traversal.is_on_ladder():
		var sliding := bool(context.get("jump_tracking", false)) and float(context.get("jump_hold_seconds", 0.0)) >= float(traversal.mantle_motor.climb_profile.ladder_slide_hold_seconds)
		slot = "ladder_slide" if sliding else ("ladder_move" if absf(velocity.y) > 0.05 else "ladder_idle")
	elif traversal.is_mantling():
		slot = str(context.get("presentation_slot", "pull_up")) if StringName(context.get("action_type", &"")) == &"climb" else "vault"
		if slot == "pull_up" and context.get("hang_style","braced") == "free": slot = "pull_up_free"
	var presentation := {"slot": slot, "height": float(context.get("height", 0.0)),
		"phase": clampf(traversal.mantle_motor.elapsed / maxf(traversal.mantle_motor.duration, 0.01), 0.0, 1.0),
		"hang_style":context.get("hang_style","braced"),"can_pull_up":context.get("can_pull_up",false),"pull_up_reason":context.get("pull_up_reason","")}
	if context.has("anchor"):
		presentation["anchor"] = context.anchor
		presentation["surface_normal"] = context.get("surface_normal", Vector3.BACK)
		if context.has("start_point") and context.has("landing_point"):
			presentation["start_point"] = context.start_point
			presentation["landing_point"] = context.landing_point
	presentation["travel_metres"] = float(context.get("travel_metres", 0.0))
	return presentation


func _try_begin_automatic_vault(desired_dir: Vector3, climbing: bool = false, fresh_jump: bool = false) -> bool:
	var deliberate_climb := climbing and fresh_jump
	if (
		not automatic_vault_enabled
		or (automatic_vault_probe_remaining > 0.0 and not deliberate_climb)
		or automatic_vault_retry_remaining > 0.0
		or posture != MotionState.STANDING
		or (motion_state not in [MotionState.STANDING, MotionState.LANDING, MotionState.AIRBORNE] if climbing else motion_state != MotionState.STANDING)
		or (not climbing and not _movement_floor_contact())
		or desired_dir.is_zero_approx()
		or (not climbing and desired_dir.length() < full_gait_input_threshold)
		or (not climbing and Vector2(velocity.x, velocity.z).length() < automatic_vault_minimum_speed)
	):
		return false
	automatic_vault_probe_remaining = maxf(automatic_vault_probe_interval, 0.02)
	if bool(get_meta("reload_action_pending", false)):
		_emit_mobility_requested(&"VAULTING")
		return false
	var collider := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider == null or not (collider.shape is CapsuleShape3D):
		return false
	var capsule := collider.shape as CapsuleShape3D
	var result := traversal.try_begin_automatic_vault(
		self,
		desired_dir,
		capsule.height,
		capsule.radius,
		climbing,
		climbing
	)
	if not bool(result.get("accepted", false)):
		return false
	automatic_vault_retry_remaining = maxf(automatic_vault_retry_seconds, 0.05)
	motion_state = MotionState.VAULTING
	action_elapsed = 0.0
	action_duration = float(result.get("duration", 0.0))
	action_direction = _safe_action_direction(desired_dir)
	_emit_mobility_started(&"VAULTING")
	return true


func _advance_automatic_vault(authoritative_aim_yaw: float, delta: float) -> void:
	if traversal.is_hanging():
		velocity = traversal.solve_grip(self, 0.0, delta).velocity
		_move_body_with_collision()
		return
	var solution := traversal.solve_mantle(global_position, delta, self)
	velocity = solution.get("velocity", Vector3.ZERO) as Vector3
	horizontal_response_mode = &"VAULTING"
	_update_orientation(action_direction, authoritative_aim_yaw, delta)
	_move_body_with_collision()
	if bool(solution.get("finished", false)):
		motion_state = posture
		velocity = Vector3(velocity.x, -0.5, velocity.z)
	was_on_floor = _movement_floor_contact()

func _handle_posture_command(command, delta: float, desired_dir: Vector3) -> void:
	if motion_state == MotionState.DIVING or motion_state == MotionState.ROLLING:
		if mobility_combo_kind == &"slide":
			if command.crouch_held:
				stance_hold_timer += delta
			if command.dive_pressed or command.prone_pressed or stance_hold_timer >= stance_hold_threshold:
				combo_exit_prone = true
				stance_held_triggered = true
		# A stance-hold dive can finish after C has already been released. Consume
		# that release while the committed action owns movement so the hold latch
		# cannot remain stuck and poison the next stance command.
		if command.crouch_released:
			stance_hold_timer = 0.0
			stance_held_triggered = false
		return

	# Retain replay/network compatibility with older movement packets. Local
	# input uses the single tap/hold stance action below.
	if command.prone_pressed:
		_try_set_posture(
			MotionState.CROUCHED if posture == MotionState.PRONE else MotionState.PRONE
		)
		return

	# Multi-function Stance Button (C / Crouch): Tap = Crouch/Stand, Hold = Drop to Prone
	if command.crouch_held:
		stance_hold_timer += delta
		if stance_hold_timer >= stance_hold_threshold and not stance_held_triggered:
			stance_held_triggered = true
			if _can_stance_hold_dive(desired_dir):
				_begin_dive(desired_dir)
			elif posture == MotionState.PRONE:
				if not _try_set_posture(MotionState.STANDING):
					_try_set_posture(MotionState.CROUCHED)
			else:
				_try_set_posture(MotionState.PRONE)

	if command.crouch_released:
		if not stance_held_triggered:
			# Quick Tap action
			var target_posture := MotionState.CROUCHED
			if posture == MotionState.PRONE:
				target_posture = MotionState.CROUCHED
			elif posture == MotionState.CROUCHED:
				target_posture = MotionState.STANDING
			_try_set_posture(target_posture)
		stance_hold_timer = 0.0
		stance_held_triggered = false

func _can_stance_hold_dive(desired_dir: Vector3) -> bool:
	if posture == MotionState.PRONE or not _movement_floor_contact():
		return false
	return (
		desired_dir.length() >= full_gait_input_threshold
		and Vector2(velocity.x, velocity.z).length() >= dive_minimum_run_speed
	)

func _begin_dive(desired_dir: Vector3) -> void:
	reset_jump_combos()
	var dive_entry_posture := posture
	action_direction = _safe_action_direction(desired_dir)
	action_elapsed = 0.0
	action_duration = dive_duration
	motion_state = MotionState.DIVING
	_emit_mobility_started(&"DIVING")
	# Preserve the stance that began the committed dive. Forcing crouch to
	# standing made the presentation anchor jump upward before falling to prone.
	posture = dive_entry_posture
	_apply_posture_collider()
	velocity.y = 2.4

func _try_begin_mobility_action(
	desired_dir: Vector3,
	input: Vector2,
	jump_started: bool,
	command
) -> bool:
	if not _movement_floor_contact() or motion_state == MotionState.DIVING or motion_state == MotionState.ROLLING or motion_state == MotionState.LANDING:
		return false

	# Jump owns one action only. Travel input must never reinterpret Space as a
	# dive; that would make the same network command produce two outcomes.
	if jump_started and posture != MotionState.PRONE:
		if not _try_set_posture(MotionState.STANDING):
			return false
		var running := input.length() >= full_gait_input_threshold and Vector2(velocity.x, velocity.z).length() >= float(traversal.mantle_motor.climb_profile.running_jump_min_speed_mps)
		active_jump_launch_speed = float(traversal.mantle_motor.climb_profile.running_jump_velocity_mps) if running else jump_velocity
		velocity.y = active_jump_launch_speed
		motion_state = MotionState.AIRBORNE
		_emit_mobility_started(&"AIRBORNE")
		return true

	# Z is the independent dive-to-prone action.
	if command.dive_pressed and posture != MotionState.PRONE:
		_begin_dive(desired_dir)
		return false

	# Retain replay/network compatibility with older movement packets. Local
	# input no longer creates a separate roll command.
	if command.roll_pressed and posture != MotionState.PRONE:
		roll_side = -1.0 if input.x < -0.1 else 1.0
		if absf(input.x) > 0.1:
			action_direction = global_basis.x * signf(input.x)
		else:
			action_direction = _safe_action_direction(desired_dir)
		action_direction.y = 0.0
		action_direction = action_direction.normalized()
		action_elapsed = 0.0
		action_duration = roll_duration
		motion_state = MotionState.ROLLING
		_emit_mobility_started(&"ROLLING")
		posture = MotionState.CROUCHED
		_apply_posture_collider()
	return false

func _safe_action_direction(desired_dir: Vector3) -> Vector3:
	var result := desired_dir
	if result.length_squared() < 0.01:
		result = -global_basis.z
	result.y = 0.0
	return result.normalized()

func _advance_committed_action(delta: float) -> void:
	if mobility_combo_kind != &"":
		_advance_jump_combo(delta)
		return
	action_elapsed = minf(action_elapsed + delta, action_duration)
	var phase := get_action_phase()
	var base_speed := dive_speed if motion_state == MotionState.DIVING else roll_speed
	var speed_scale := lerpf(1.0, 0.32, phase)
	velocity.x = action_direction.x * base_speed * speed_scale
	velocity.z = action_direction.z * base_speed * speed_scale
	if not _movement_floor_contact():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.5
	if action_elapsed >= action_duration:
		if motion_state == MotionState.DIVING:
			posture = MotionState.PRONE
		else:
			posture = MotionState.CROUCHED
		motion_state = posture
		_apply_posture_collider()

func _finish_committed_action_on_collision() -> void:
	if get_slide_collision_count() <= 0:
		return
	for collision_index in range(get_slide_collision_count()):
		var collision := get_slide_collision(collision_index)
		if absf(collision.get_normal().y) < 0.55:
			if mobility_combo_kind != &"":
				combo_wall_blocked = true
				velocity.x = 0.0
				velocity.z = 0.0
				return # Keep gravity/recovery; do not switch to an airborne stand.
			action_elapsed = action_duration
			posture = (
				MotionState.PRONE
				if motion_state == MotionState.DIVING
				else MotionState.CROUCHED
			)
			motion_state = posture
			velocity.x = 0.0
			velocity.z = 0.0
			_apply_posture_collider()
			return

func _update_air_and_landing_state(delta: float) -> void:
	if not _movement_floor_contact():
		motion_state = MotionState.AIRBORNE
		return
	if not was_on_floor and motion_state == MotionState.AIRBORNE:
		jump_combo_intent.armed = false
		if pending_jump_slide:
			pending_jump_slide = false
			_begin_jump_combo(&"slide", combo_direction)
			return
		motion_state = MotionState.LANDING
		action_elapsed = 0.0
		action_duration = landing_recovery
	elif motion_state == MotionState.LANDING:
		action_elapsed += delta
		if action_elapsed >= action_duration:
			motion_state = posture
			active_jump_launch_speed = jump_velocity
	elif motion_state != MotionState.DIVING and motion_state != MotionState.ROLLING:
		motion_state = posture

func _apply_posture_collider() -> void:
	var collider := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider == null or not (collider.shape is CapsuleShape3D):
		return
	var capsule := collider.shape as CapsuleShape3D
	var target_height := 1.85
	if posture == MotionState.CROUCHED:
		target_height = 1.25
	elif posture == MotionState.PRONE:
		target_height = 0.82
	capsule.height = target_height
	collider.position.y = target_height * 0.5
	collider.position.x = peek_amount * 0.38
	if mobility_combo_kind != &"":
		capsule.height = float(jump_combo_intent.profile.collider_height)
		collider.position.y = capsule.height * 0.5

func _try_set_posture(target_posture: int) -> bool:
	if target_posture == posture:
		return true
	if _posture_height(target_posture) > _posture_height(posture):
		if not _has_posture_clearance(target_posture):
			return false
	posture = target_posture
	motion_state = posture
	_apply_posture_collider()
	return true

func _posture_height(target_posture: int) -> float:
	if target_posture == MotionState.PRONE:
		return 0.82
	if target_posture == MotionState.CROUCHED:
		return 1.25
	return 1.85

func _has_posture_clearance(target_posture: int) -> bool:
	var collider := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider == null or not (collider.shape is CapsuleShape3D):
		return true
	var current_capsule := collider.shape as CapsuleShape3D
	var current_height: float = current_capsule.height
	var target_height: float = _posture_height(target_posture)
	var space := get_world_3d().direct_space_state
	var ray_offsets: Array[Vector3] = [
		Vector3.ZERO,
		Vector3.RIGHT * current_capsule.radius * 0.65,
		Vector3.LEFT * current_capsule.radius * 0.65,
		Vector3.FORWARD * current_capsule.radius * 0.65,
		Vector3.BACK * current_capsule.radius * 0.65,
	]
	for offset in ray_offsets:
		var ray := PhysicsRayQueryParameters3D.create(
			global_position + offset + Vector3.UP * (current_height + 0.01),
			global_position + offset + Vector3.UP * (target_height + 0.03),
			collision_mask,
			[get_rid()]
		)
		ray.collide_with_areas = false
		var clearance_hit := space.intersect_ray(ray)
		if not clearance_hit.is_empty():
			return false
	var probe := CapsuleShape3D.new()
	probe.radius = current_capsule.radius
	probe.height = target_height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.transform = Transform3D(
		global_basis,
		global_position + Vector3.UP * (probe.height * 0.5 + 0.015)
	)
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	return space.intersect_shape(query, 1).is_empty()

func get_action_phase() -> float:
	if action_duration <= 0.0:
		return 0.0
	return clampf(action_elapsed / action_duration, 0.0, 1.0)

func reset_jump_combos() -> void:
	jump_combo_intent.reset()
	pending_jump_slide = false
	mobility_combo_kind = &""
	combo_wall_blocked = false
	combo_recovering = false
	combo_rest_input_released = false
	combo_exit_prone = false

func get_mobility_combo_clip() -> StringName:
	if motion_state != MotionState.DIVING:
		return &""
	if mobility_combo_kind == &"slide" and combo_exit_prone:
		return StringName(jump_combo_intent.profile.clips.slide_prone)
	if posture == MotionState.CROUCHED and jump_combo_intent.profile.crouch_clips.has(String(mobility_combo_kind)):
		return StringName(jump_combo_intent.profile.crouch_clips[String(mobility_combo_kind)])
	return StringName(jump_combo_intent.profile.clips.get(String(mobility_combo_kind), ""))

func _update_jump_combo(command, launched: bool, delta: float) -> void:
	var chain_allowed: bool = String(mobility_combo_kind) in jump_combo_intent.profile.chain_from and not combo_exit_prone
	var eligible: bool = not launched and (chain_allowed or (_movement_floor_contact() and motion_state in [MotionState.STANDING, MotionState.CROUCHED]))
	var choice: StringName = jump_combo_intent.step(command.direction_held_mask, eligible, delta)
	if choice == &"" or (mobility_combo_kind != &"" and (not chain_allowed or String(choice) not in jump_combo_intent.profile.chain_to)):
		return
	if mobility_combo_kind == &"" and posture == MotionState.CROUCHED and String(choice) not in jump_combo_intent.profile.crouch_allowed_kinds:
		return
	var local_direction := jump_combo_intent.action_local_direction(choice, command.direction_held_mask)
	combo_direction = Basis(Vector3.UP, command.aim_yaw) * local_direction
	_begin_jump_combo(choice, combo_direction)

func _begin_jump_combo(kind: StringName, direction: Vector3) -> void:
	mobility_combo_kind = kind
	jump_combo_intent.armed = false
	pending_jump_slide = false
	combo_wall_blocked = false
	combo_recovering = false
	combo_rest_input_released = false
	combo_exit_prone = false
	action_direction = direction.normalized()
	action_elapsed = 0.0
	action_duration = float(jump_combo_intent.profile.slide_duration if kind == &"slide" else jump_combo_intent.profile.dive_duration)
	motion_state = MotionState.DIVING # Reuse existing full-body mobility ownership.
	_apply_posture_collider()
	# Grounded action: animation never adds a second movement/impulse owner.
	_emit_mobility_started(&"DIVING")

func _advance_jump_combo(delta: float) -> void:
	action_elapsed = minf(action_elapsed + delta, action_duration)
	var rest_time := float(jump_combo_intent.profile.get("rest_seconds", 1.05))
	var move_unlock := clampf(float(jump_combo_intent.profile.get("slide_move_unlock_seconds", action_duration)), 0.0, action_duration)
	if mobility_combo_kind == &"slide" and not combo_exit_prone and _movement_floor_contact() and action_elapsed >= move_unlock and movement_input_strength > 0.1:
		# Keep a fresh perpendicular first tap so its second tap can dive from crouch.
		var first_bit := jump_combo_intent.first_bit
		var armed := jump_combo_intent.armed
		var tap_age := jump_combo_intent.tap_age
		_finish_jump_combo()
		jump_combo_intent.first_bit = first_bit
		jump_combo_intent.armed = armed
		jump_combo_intent.tap_age = tap_age
		return
	if mobility_combo_kind in [&"left", &"right"] and action_elapsed >= rest_time and not combo_recovering:
		if _movement_floor_contact() and movement_input_strength <= 0.1:
			combo_rest_input_released = true
		if _movement_floor_contact() and movement_input_strength > 0.1 and combo_rest_input_released:
			combo_recovering = true
		else:
			action_elapsed = rest_time # Held combo tap cannot also request get-up.
	var speed := float(jump_combo_intent.profile.slide_speed if mobility_combo_kind == &"slide" else jump_combo_intent.profile.dive_speed)
	var deceleration := 1.0 - smoothstep(0.0, rest_time, action_elapsed)
	if combo_wall_blocked:
		deceleration = 0.0
	velocity.x = action_direction.x * speed * deceleration
	velocity.z = action_direction.z * speed * deceleration
	velocity.y = velocity.y - gravity * delta if not _movement_floor_contact() else -0.5
	# Before the authored get-up starts, abandon it if standing would hit a roof.
	if _movement_floor_contact() and action_elapsed >= rest_time and combo_recovering and not _has_posture_clearance(MotionState.STANDING):
		_finish_jump_combo()
	elif _movement_floor_contact() and action_elapsed >= action_duration:
		_finish_jump_combo()

func _finish_jump_combo() -> void:
	var finish_crouched: bool = String(mobility_combo_kind) in jump_combo_intent.profile.get("crouch_finish_kinds", [])
	var finish_prone := combo_exit_prone
	var held_at_finish := jump_combo_intent.previous_mask
	reset_jump_combos()
	jump_combo_intent.previous_mask = held_at_finish # Completion is not a fresh key edge.
	posture = MotionState.PRONE if finish_prone else MotionState.CROUCHED
	motion_state = posture
	_apply_posture_collider()
	if not finish_crouched and not finish_prone:
		_try_set_posture(MotionState.STANDING) # Side get-up still respects headroom.
	velocity.x = 0.0
	velocity.z = 0.0

func get_motion_state_name() -> StringName:
	match motion_state:
		MotionState.CROUCHED:
			return &"CROUCHED"
		MotionState.PRONE:
			return &"PRONE"
		MotionState.AIRBORNE:
			return &"AIRBORNE"
		MotionState.LANDING:
			return &"LANDING"
		MotionState.DIVING:
			return &"DIVING"
		MotionState.ROLLING:
			return &"ROLLING"
		MotionState.VAULTING:
			return &"VAULTING"
		_:
			return &"STANDING"

func get_posture_name() -> StringName:
	if posture == MotionState.PRONE:
		return &"PRONE"
	if posture == MotionState.CROUCHED:
		return &"CROUCHED"
	return &"STANDING"


# Replay uses the acknowledged contact for the first step; the collision move refreshes it.
var prediction_floor_override: int = -1
var prediction_replaying: bool = false

func _movement_floor_contact() -> bool:
	return bool(prediction_floor_override) if prediction_floor_override >= 0 else is_on_floor()

func _move_body_with_collision(delta: float = 1.0 / 60.0) -> void:
	var ordinary_grounded := bool(StepProbe.profile.enabled) and _movement_floor_contact() and velocity.y <= 0.0 and posture != MotionState.PRONE and motion_state in [MotionState.STANDING, MotionState.CROUCHED, MotionState.LANDING] and not traversal.is_active()
	var original_snap := floor_snap_length
	if ordinary_grounded:
		var lift := StepProbe.lift(self, Vector3(velocity.x, 0, velocity.z) * delta)
		if lift > 0.0: move_and_collide(Vector3.UP * lift)
		floor_snap_length = maxf(original_snap, float(StepProbe.profile.maximum_step_down_m))
	prediction_floor_override = -1
	move_and_slide()
	if ordinary_grounded: apply_floor_snap()
	if ordinary_grounded and not is_on_floor():
		var snap := StepProbe.edge_snap_distance(self)
		if snap >= 0.0:
			move_and_collide(Vector3.DOWN * snap)
			# Existing replay contact contract also carries this verified tread contact.
			prediction_floor_override = 1
	floor_snap_length = original_snap

func _emit_mobility_started(kind: StringName) -> void:
	if not prediction_replaying: mobility_action_started.emit(kind)

func _emit_mobility_requested(kind: StringName) -> void:
	if not prediction_replaying: mobility_action_requested.emit(kind)
