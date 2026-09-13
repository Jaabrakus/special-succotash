class_name SocomNetworkOperator
extends SocomTestPlayer

## A network combatant built from the exact operator, animation and anatomical
## hurtbox components used by the canonical playground. CharacterBody remains
## movement authority; animated Area3D shapes remain damage-only geometry.

const MannequinScript := preload("res://scripts/player/test_mannequin.gd")
const MovementState := preload("res://scripts/network/socom_movement_state.gd")
const TeamAppearance := preload("res://scripts/player/operator_team_appearance.gd")
const AnimatedHurtboxRigScript := preload("res://scripts/combat/socom_animated_hurtbox_rig.gd")
const SourceFirearmDamage := preload("res://scripts/combat/source_firearm_damage.gd")
const SourceFirearmPolicy := preload("res://scripts/weapons/source_firearm_policy.gd")
var source_health: RefCounted = null

signal eliminated(victim_peer_id: int, attacker_peer_id: int)

var network_peer_id: int = 0
var team_id: int = 0
var display_name: String = "OPERATOR"
var alive: bool = true
var round_deactivated: bool = false
var mannequin: SocomTestMannequin
var hurtbox_rig: SocomAnimatedHurtboxRig
var nameplate: Label3D
var team_visual_color := Color.WHITE
var carrying_demolition_bomb: bool = false


var snapshot_history: Array[Dictionary] = []
var interpolation_delay_seconds: float = 0.130
var is_proxy_replica: bool = false
var authoritative_hurtboxes_enabled: bool = true
var visual_runtime_enabled: bool = true
var pending_position_correction := Vector3.ZERO
var prediction_enabled := false
var complete_prediction_enabled := false
var full_prediction_history: Dictionary = {}
var pending_action_correction: Dictionary = {}
var last_action_ack := -1
var last_action_epoch := -1
var action_replay_count := 0
var network_command_driven := false
var prediction_history := preload("res://scripts/network/socom_prediction_history.gd").new()
var consumed_input_tick := -1
var respawn_revision := 0
var received_respawn_revision := 0
var network_aim_angles := Vector2.ZERO


func _ready() -> void:
	_ensure_movement_collider()
	if not visual_runtime_enabled:
		return
	_ensure_operator_visual()
	_build_nameplate()
	call_deferred("_bind_animated_hurtboxes")


func _physics_process(delta: float) -> void:
	if complete_prediction_enabled and not pending_action_correction.is_empty():
		_reconcile_action_state()
	if not alive:
		velocity = Vector3.ZERO
		return
	if is_proxy_replica:
		# Proxy replicas are driven smoothly by snapshot interpolation in _process.
		# CharacterBody physics step does not simulate movement commands for proxies.
		return
	# A remote authority must not insert local/neutral commands between delayed
	# client inputs. One received input gets one canonical simulation step.
	if network_command_driven and movement_command_queue.is_empty():
		return
	super(delta)
	if last_movement_command != null:
		consumed_input_tick = int(last_movement_command.simulation_tick)
		network_aim_angles = Vector2(last_movement_command.aim_yaw, last_movement_command.aim_pitch)
		if prediction_enabled:
			prediction_history.record(consumed_input_tick, global_position, posture)
		if complete_prediction_enabled:
			full_prediction_history[consumed_input_tick] = {"command": last_movement_command.duplicate_command(), "state": MovementState.capture(self)}
			while full_prediction_history.size() > int(MovementState.profile.history_ticks):
				full_prediction_history.erase(full_prediction_history.keys()[0])
	if not pending_position_correction.is_zero_approx():
		var correction := pending_position_correction * (1.0 - exp(-12.0 * delta))
		var before := global_position
		move_and_collide(correction)
		var applied := global_position - before
		prediction_history.applied(applied)
		pending_position_correction -= applied


func queue_action_correction(packet: Dictionary) -> void:
	if not complete_prediction_enabled or is_proxy_replica:
		return
	if typeof(packet.get("tick")) != TYPE_INT or typeof(packet.get("epoch")) != TYPE_INT or not packet.get("state") is PackedByteArray:
		return
	if int(packet.epoch) < received_respawn_revision:
		return
	if not pending_action_correction.is_empty():
		if int(packet.epoch) < int(pending_action_correction.epoch): return
		if int(packet.epoch) == int(pending_action_correction.epoch) and int(packet.tick) <= int(pending_action_correction.tick): return
	pending_action_correction = packet.duplicate(true)


func _reconcile_action_state() -> void:
	var packet := pending_action_correction
	pending_action_correction = {}
	var state := MovementState.unpack(packet.state)
	if state.is_empty(): return
	var fresh_life := int(packet.epoch) > last_action_epoch
	if int(packet.epoch) < received_respawn_revision: return
	if not alive and not fresh_life: return
	if fresh_life:
		full_prediction_history.clear()
		prediction_history.clear()
		movement_command_queue.clear()
		last_action_ack = -1
		received_respawn_revision = int(packet.epoch)
		last_action_epoch = int(packet.epoch)
	var tick := int(packet.tick)
	if tick <= last_action_ack and not fresh_life: return
	last_action_ack = tick
	var past: Dictionary = full_prediction_history.get(tick, {})
	var differs := fresh_life or past.is_empty() or not MovementState.agrees(past.state, state)
	for key in full_prediction_history.keys():
		if int(key) <= tick: full_prediction_history.erase(key)
	if not differs: return
	if past.is_empty(): full_prediction_history.clear()
	var live_commands := movement_command_queue.duplicate()
	movement_command_queue.clear()
	pending_position_correction = Vector3.ZERO
	MovementState.apply(self, state)
	var ticks := full_prediction_history.keys()
	ticks.sort()
	prediction_replaying = true
	var signals_blocked: bool = traversal.state_machine.is_blocking_signals()
	traversal.state_machine.set_block_signals(true)
	for replay_tick in ticks:
		movement_command_queue.append(full_prediction_history[replay_tick].command.duplicate_command())
		super._physics_process(1.0 / float(Engine.physics_ticks_per_second))
		full_prediction_history[replay_tick].state = MovementState.capture(self)
	traversal.state_machine.set_block_signals(signals_blocked)
	prediction_replaying = false
	movement_command_queue.assign(live_commands)
	action_replay_count += 1


func configure_identity(peer_id: int, assigned_team: int) -> void:
	network_peer_id = peer_id
	team_id = assigned_team
	network_aim_angles = Vector2(rotation.y, 0.0)
	display_name = "SEAL %d" % peer_id
	team_visual_color = TeamAppearance.color_for(team_id)
	if nameplate:
		_refresh_nameplate()
	call_deferred("_apply_team_visual")


func set_replica_mode(enabled: bool) -> void:
	is_proxy_replica = enabled
	replay_override_active = enabled
	set_local_input_enabled(not enabled)


func configure_network_presentation(
	is_local_visual_owner: bool,
	requires_authoritative_hurtboxes: bool
) -> void:
	authoritative_hurtboxes_enabled = requires_authoritative_hurtboxes
	if mannequin != null:
		mannequin.set_legacy_procedural_updates_enabled(is_local_visual_owner)
	_apply_hurtbox_runtime_mode()


func push_network_snapshot(
	position_value: Vector3,
	yaw_value: float,
	velocity_value: Vector3,
	posture_value: int,
	health_value: float,
	alive_value: bool,
	timestamp_seconds: float,
	presentation: Dictionary = {}
) -> void:
	var entry := {
		"time": timestamp_seconds,
		"position": position_value,
		"yaw": yaw_value,
		"velocity": velocity_value,
		"posture": posture_value,
		"health": health_value,
		"alive": alive_value,
		"presentation": presentation.duplicate(true),
	}
	
	# Insert in sorted order by timestamp
	var insert_idx := snapshot_history.size()
	while insert_idx > 0 and snapshot_history[insert_idx - 1]["time"] > timestamp_seconds:
		insert_idx -= 1
	snapshot_history.insert(insert_idx, entry)
	
	# Prune old snapshots (keep up to 1.5 seconds of history)
	var cutoff := timestamp_seconds - 1.5
	while snapshot_history.size() > 2 and snapshot_history[0]["time"] < cutoff:
		snapshot_history.pop_front()


func update_proxy_interpolation(current_time_seconds: float) -> void:
	if not is_proxy_replica or snapshot_history.is_empty():
		return
	var render_time := current_time_seconds - interpolation_delay_seconds
	
	# If render time is past the latest snapshot (jitter / slight packet delay),
	# smoothly dead-reckon along last velocity for up to 80ms.
	var latest: Dictionary = snapshot_history.back()
	if render_time >= float(latest["time"]):
		var extrapolation := minf(render_time - float(latest["time"]), 0.08)
		global_position = Vector3(latest["position"]) + Vector3(latest["velocity"]) * extrapolation
		rotation.y = float(latest["yaw"])
		velocity = Vector3(latest["velocity"])
		posture = clampi(int(latest["posture"]), MotionState.STANDING, MotionState.PRONE)
		motion_state = posture
		_apply_snapshot_presentation(latest)
		_advance_proxy_action_time(extrapolation)
		_apply_posture_collider()
		_set_alive_and_health(bool(latest["alive"]), float(latest["health"]))
		return

	# If render time is older than the oldest snapshot, clamp to oldest.
	var oldest: Dictionary = snapshot_history.front()
	if render_time <= float(oldest["time"]) or snapshot_history.size() == 1:
		global_position = Vector3(oldest["position"])
		rotation.y = float(oldest["yaw"])
		velocity = Vector3(oldest["velocity"])
		posture = clampi(int(oldest["posture"]), MotionState.STANDING, MotionState.PRONE)
		motion_state = posture
		_apply_snapshot_presentation(oldest)
		_apply_posture_collider()
		_set_alive_and_health(bool(oldest["alive"]), float(oldest["health"]))
		return

	# Find bounding snapshots s0 and s1
	var s0: Dictionary = oldest
	var s1: Dictionary = latest
	for i in range(snapshot_history.size() - 1):
		var t0 := float(snapshot_history[i]["time"])
		var t1 := float(snapshot_history[i + 1]["time"])
		if render_time >= t0 and render_time <= t1:
			s0 = snapshot_history[i]
			s1 = snapshot_history[i + 1]
			break

	var duration := maxf(float(s1["time"]) - float(s0["time"]), 0.0001)
	var alpha := clampf((render_time - float(s0["time"])) / duration, 0.0, 1.0)

	var p0: Vector3 = s0["position"]
	var p1: Vector3 = s1["position"]
	var y0: float = s0["yaw"]
	var y1: float = s1["yaw"]
	var v0: Vector3 = s0["velocity"]
	var v1: Vector3 = s1["velocity"]

	# Hermite / smooth interpolation between positions
	var smooth_alpha := smoothstep(0.0, 1.0, alpha)
	global_position = p0.lerp(p1, smooth_alpha)
	rotation.y = lerp_angle(y0, y1, alpha)
	velocity = v0.lerp(v1, alpha)

	var chosen_posture := int(s1["posture"] if alpha >= 0.5 else s0["posture"])
	posture = clampi(chosen_posture, MotionState.STANDING, MotionState.PRONE)
	motion_state = posture
	_apply_snapshot_presentation(s1 if alpha >= 0.5 else s0)
	var p_start: Dictionary = s0.get("presentation", {})
	var p_end: Dictionary = s1.get("presentation", {})
	if (int(p_start.get("motion_state", -1)) == int(p_end.get("motion_state", -2))
		and String(p_start.get("combo_kind", "")) == String(p_end.get("combo_kind", ""))
		and bool(p_start.get("combo_recovering", false)) == bool(p_end.get("combo_recovering", false))
		and float(p_end.get("action_elapsed", 0.0)) >= float(p_start.get("action_elapsed", 0.0))):
		action_elapsed = clampf(lerpf(float(p_start.get("action_elapsed", 0.0)), float(p_end.get("action_elapsed", 0.0)), alpha), 0.0, action_duration)
	_apply_posture_collider()

	var blended_health := lerpf(float(s0["health"]), float(s1["health"]), alpha)
	var blended_alive := bool(s1["alive"]) if alpha >= 0.5 else bool(s0["alive"])
	_set_alive_and_health(blended_alive, blended_health)


func get_animation_aim_state() -> Dictionary:
	if not network_command_driven and not is_proxy_replica:
		return {} # The owning player keeps the real camera/reticle aim.
	var direction := Vector3(-sin(network_aim_angles.x) * cos(network_aim_angles.y),
		sin(network_aim_angles.y), -cos(network_aim_angles.x) * cos(network_aim_angles.y))
	var height := 1.35 if posture == MotionState.STANDING else (0.95 if posture == MotionState.CROUCHED else 0.45)
	return {"angles": network_aim_angles, "target": global_position + Vector3.UP * height + direction * 100.0}


var network_traversal_presentation: Dictionary = {}

func get_traversal_presentation() -> Dictionary:
	return network_traversal_presentation if is_proxy_replica else super.get_traversal_presentation()

func _apply_snapshot_presentation(entry: Dictionary) -> void:
	var state: Dictionary = entry.get("presentation", {})
	var launch := float(state.get("jump_launch_speed", jump_velocity))
	active_jump_launch_speed = clampf(launch, 1.0, 10.0) if is_finite(launch) else jump_velocity
	network_traversal_presentation = {}
	var traversal_value: Variant = state.get("traversal", {})
	if traversal_value is Dictionary and str(traversal_value.get("slot", "")) in ["hang", "pull_up", "low_mantle", "vault", "ladder_idle", "ladder_move", "ladder_slide"]:
		var height := float(traversal_value.get("height", 0.0))
		var phase := float(traversal_value.get("phase", 0.0))
		if is_finite(height) and is_finite(phase):
			network_traversal_presentation = {"slot": str(traversal_value.slot), "height": clampf(height, 0.0, 1000.0), "phase": clampf(phase, 0.0, 1.0)}
			var anchor: Variant = traversal_value.get("anchor")
			var normal: Variant = traversal_value.get("surface_normal")
			if anchor is Vector3 and normal is Vector3 and anchor.is_finite() and normal.is_finite() and normal.length_squared() > 0.01:
				network_traversal_presentation["anchor"] = anchor
				network_traversal_presentation["surface_normal"] = normal.normalized()
			for key in ["start_point", "landing_point"]:
				var point: Variant = traversal_value.get(key)
				if point is Vector3 and point.is_finite():
					network_traversal_presentation[key] = point
	round_deactivated = bool(state.get("round_deactivated", false))
	if mannequin != null:
		mannequin.visible = not round_deactivated
	motion_state = clampi(int(state.get("motion_state", posture)), MotionState.STANDING, MotionState.VAULTING)
	var combo := StringName(state.get("combo_kind", ""))
	mobility_combo_kind = combo if combo in [&"slide", &"left", &"right", &"back"] and motion_state == MotionState.DIVING else &""
	combo_exit_prone = mobility_combo_kind == &"slide" and bool(state.get("combo_exit_prone", false))
	combo_recovering = bool(state.get("combo_recovering", false))
	roll_side = clampf(float(state.get("roll_side", 1.0)), -1.0, 1.0)
	var direction: Vector3 = state.get("action_direction", Vector3.FORWARD)
	if direction.is_finite(): action_direction = direction.normalized()
	action_duration = clampf(float(state.get("action_duration", 0.0)), 0.0, 3.0)
	action_elapsed = clampf(float(state.get("action_elapsed", 0.0)), 0.0, action_duration)
	var angles: Vector2 = state.get("aim_angles", Vector2(rotation.y, 0.0))
	if angles.is_finite(): network_aim_angles = angles
	var desired: Vector3 = state.get("desired_movement", Vector3.ZERO)
	desired_movement_direction = desired.limit_length(1.0) if desired.is_finite() else Vector3.ZERO
	movement_input_strength = clampf(float(state.get("movement_strength", 0.0)), 0.0, 1.0)
	peek_amount = clampf(float(state.get("peek", 0.0)), -1.0, 1.0)


func _advance_proxy_action_time(seconds: float) -> void:
	if motion_state not in [MotionState.DIVING, MotionState.ROLLING, MotionState.LANDING]: return
	var limit := action_duration
	if mobility_combo_kind in [&"left", &"right"] and not combo_recovering:
		limit = minf(limit, float(jump_combo_intent.profile.rest_seconds))
	action_elapsed = minf(action_elapsed + maxf(seconds, 0.0), limit)


func set_authoritative_snapshot(
	position_value: Vector3,
	yaw_value: float,
	velocity_value: Vector3,
	posture_value: int,
	health_value: float,
	alive_value: bool,
	hard_snap: bool = false,
	acknowledged_input_tick: int = -1,
	server_respawn_revision: int = 0
) -> void:
	if server_respawn_revision < received_respawn_revision:
		return
	if complete_prediction_enabled and not hard_snap:
		# Health and movement packets may cross in flight. Neither may rewind a
		# newer life, and health snapshots must not overwrite replayed movement.
		received_respawn_revision = server_respawn_revision
		_set_alive_and_health(alive_value, health_value)
		return
	if prediction_enabled and not hard_snap and server_respawn_revision == received_respawn_revision:
		var acknowledgement := prediction_history.acknowledge(acknowledged_input_tick, position_value)
		if not acknowledgement.is_empty():
			var error: Vector3 = acknowledgement.error
			if error.length() > 1.25:
				# Preserve all movement newer than the acknowledged input.
				global_position += error
				prediction_history.applied(error)
				pending_position_correction = Vector3.ZERO
			else:
				pending_position_correction = error
			if posture == int(acknowledgement.posture) and posture != posture_value:
				posture = clampi(posture_value, MotionState.STANDING, MotionState.PRONE)
				motion_state = posture
				_apply_posture_collider()
		_set_alive_and_health(alive_value, health_value)
		return
	if server_respawn_revision != received_respawn_revision:
		hard_snap = true
		received_respawn_revision = server_respawn_revision
		prediction_history.clear()
	if hard_snap or global_position.distance_to(position_value) > 1.25:
		reset_jump_combos()
		pending_position_correction = Vector3.ZERO
		global_position = position_value
		rotation.y = yaw_value
		velocity = velocity_value
	else:
		# Do not rewind locally predicted velocity/yaw on every delayed packet.
		# The CharacterBody physics step consumes bounded positional corrections.
		pending_position_correction = position_value - global_position
	var server_posture := clampi(posture_value, MotionState.STANDING, MotionState.PRONE)
	if hard_snap or posture != server_posture:
		posture = server_posture
		motion_state = posture
		_apply_posture_collider()
	_set_alive_and_health(alive_value, health_value)


func respawn_at(spawn_position: Vector3) -> void:
	source_health = null
	round_deactivated = false
	lean_latch.reset()
	peek_amount = 0.0
	reset_jump_combos()
	respawn_revision += 1
	consumed_input_tick = -1
	movement_command_queue.clear()
	prediction_history.clear()
	pending_position_correction = Vector3.ZERO
	full_prediction_history.clear()
	pending_action_correction.clear()
	last_action_ack = -1
	last_action_epoch = -1
	prediction_floor_override = -1
	snapshot_history.clear()
	global_position = spawn_position
	velocity = Vector3.ZERO
	posture = MotionState.STANDING
	motion_state = MotionState.STANDING
	_apply_posture_collider()
	_set_alive_and_health(true, max_health)
	set_bomb_carrier(false)


func deactivate_for_round() -> void:
	round_deactivated = true
	lean_latch.reset()
	peek_amount = 0.0
	reset_jump_combos()
	pending_position_correction = Vector3.ZERO
	# The operator remains network-visible for spectating, but cannot move,
	# collide, fire, or receive damage while its teammate fights sudden death.
	snapshot_history.clear()
	velocity = Vector3.ZERO
	set_bomb_carrier(false)
	_set_alive_and_health(false, 0.0)


func set_bomb_carrier(active: bool) -> void:
	carrying_demolition_bomb = active
	if mannequin != null:
		mannequin.set_bomb_backpack_visible(active)


func take_source_bullet_damage(combat: Dictionary, hit_region: StringName, attacker_peer_id: int = 0) -> Dictionary:
	if not multiplayer.is_server() or not alive or not SourceFirearmPolicy.valid_impact(combat, hit_region):
		return {"accepted": false, "hit_region": hit_region}
	if source_health == null:
		source_health = SourceFirearmDamage.new()
		if not source_health.initialize(SourceFirearmPolicy.multiplayer_defaults()):
			source_health = null
			return {"accepted": false, "reason": "SOURCE_HEALTH_PROFILE_INVALID"}
		source_health.cap_legacy_health_ratio(current_health / maxf(max_health, 0.001))
	var before_health := current_health
	var result: Dictionary = source_health.apply_projectile(combat.impact_damage, combat.damage_modifier,
		combat.piercing, float(combat.get("distance_m", INF)), combat.effective_range_m,
		combat.maximum_range_m, SourceFirearmPolicy.source_region(hit_region))
	if not bool(result.get("accepted", false)): return result
	current_health = max_health * source_health.weighted_health_ratio()
	if not source_health.alive:
		_set_alive_and_health(false, 0.0)
		eliminated.emit(network_peer_id, attacker_peer_id)
	else:
		_refresh_nameplate()
	result.merge({"damage": before_health - current_health, "hit_region": hit_region, "headshot": hit_region == &"HEAD", "remaining_health": current_health,
		"eliminated": not alive, "victim_peer_id": network_peer_id, "damage_model": SourceFirearmPolicy.DAMAGE_MODEL}, true)
	return result


func take_bullet_damage_region(
	base_damage: float,
	hit_region: StringName,
	_hit_position: Vector3,
	_hit_normal: Vector3,
	_shooter_origin: Vector3 = Vector3.ZERO,
	attacker_peer_id: int = 0,
	headshot_multiplier: float = 3.5
) -> Dictionary:
	if not multiplayer.is_server() or not alive:
		return {"accepted": false, "hit_region": hit_region}
	var region := String(hit_region)
	var multiplier := 1.0
	if region == "HEAD":
		multiplier = clampf(headshot_multiplier, 1.0, 10.0)
	elif (
		"ARM" in region
		or "LEG" in region
		or "THIGH" in region
		or "CALF" in region
		or "FOOT" in region
	):
		multiplier = 0.48
	elif region == "PELVIS":
		multiplier = 0.72
	var damage := maxf(0.0, base_damage * multiplier)
	current_health = maxf(0.0, current_health - damage)
	if source_health != null: source_health.cap_legacy_health_ratio(current_health / maxf(max_health, 0.001))
	if current_health <= 0.0:
		_set_alive_and_health(false, 0.0)
		eliminated.emit(network_peer_id, attacker_peer_id)
	else:
		_refresh_nameplate()
	return {
		"accepted": true,
		"hit_region": hit_region,
		"headshot": region == "HEAD",
		"damage": damage,
		"remaining_health": current_health,
		"eliminated": not alive,
		"victim_peer_id": network_peer_id,
	}


func take_explosion_damage(
	damage_value: float,
	_explosion_origin: Vector3,
	attacker_peer_id: int = 0
) -> Dictionary:
	if not multiplayer.is_server() or not alive:
		return {"accepted": false}
	var damage := maxf(0.0, damage_value)
	current_health = maxf(0.0, current_health - damage)
	if source_health != null: source_health.cap_legacy_health_ratio(current_health / maxf(max_health, 0.001))
	if current_health <= 0.0:
		_set_alive_and_health(false, 0.0)
		eliminated.emit(network_peer_id, attacker_peer_id)
	else:
		_refresh_nameplate()
	return {
		"accepted": damage > 0.0,
		"damage": damage,
		"remaining_health": current_health,
		"eliminated": not alive,
		"victim_peer_id": network_peer_id,
	}


func _set_alive_and_health(value: bool, health_value: float) -> void:
	alive = value
	if alive:
		round_deactivated = false
	if not alive:
		reset_jump_combos()
	current_health = clampf(health_value, 0.0, max_health)
	collision_layer = 1 if alive else 0
	if mannequin:
		mannequin.visible = not round_deactivated
	if hurtbox_rig:
		hurtbox_rig.set_enabled(alive and authoritative_hurtboxes_enabled)
	_refresh_nameplate()

func is_dead_for_presentation() -> bool:
	return not alive or current_health <= 0.0


func _ensure_movement_collider() -> void:
	if get_node_or_null("CollisionShape3D") != null:
		return
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.85
	collider.shape = capsule
	collider.position.y = 0.925
	add_child(collider)


func _ensure_operator_visual() -> void:
	mannequin = get_node_or_null("Mannequin") as SocomTestMannequin
	if mannequin != null:
		return
	mannequin = MannequinScript.new() as SocomTestMannequin
	mannequin.name = "Mannequin"
	add_child(mannequin)


func _build_nameplate() -> void:
	nameplate = Label3D.new()
	nameplate.name = "NetworkNameplate"
	nameplate.position = Vector3(0.0, 2.25, 0.0)
	nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nameplate.font_size = 20
	nameplate.outline_size = 5
	nameplate.visible = false
	add_child(nameplate)
	_refresh_nameplate()


func _refresh_nameplate() -> void:
	if nameplate == null:
		return
	nameplate.visible = false
	nameplate.text = ""



func _apply_team_visual() -> void:
	if mannequin == null or mannequin.production_animation == null:
		return
	var model := mannequin.production_animation.get_node_or_null("TrooperModel")
	# The owning player's view keeps the canonical solo appearance. Other
	# operators retain team colors; team identity/gameplay are not changed.
	var color_name := String(TeamAppearance.profile().get("solo_color", "")) if network_peer_id == multiplayer.get_unique_id() else ""
	TeamAppearance.apply(model, team_id, color_name)


func _bind_animated_hurtboxes() -> void:
	await get_tree().process_frame
	if mannequin == null or mannequin.production_animation == null:
		return
	var skeleton := mannequin.production_animation.skeleton as Skeleton3D
	if skeleton == null:
		push_warning("Network operator could not bind animated hurtboxes")
		return
	hurtbox_rig = AnimatedHurtboxRigScript.new() as SocomAnimatedHurtboxRig
	hurtbox_rig.name = "AnimatedHurtboxes"
	add_child(hurtbox_rig)
	hurtbox_rig.bind(skeleton, self)
	hurtbox_rig.set_debug_visible(false)
	_apply_hurtbox_runtime_mode()


func _apply_hurtbox_runtime_mode() -> void:
	if hurtbox_rig == null:
		return
	hurtbox_rig.set_physics_process(authoritative_hurtboxes_enabled)
	hurtbox_rig.set_enabled(alive and authoritative_hurtboxes_enabled)
