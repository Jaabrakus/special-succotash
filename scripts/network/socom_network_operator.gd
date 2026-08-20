class_name SocomNetworkOperator
extends SocomTestPlayer

## A network combatant built from the exact operator, animation and anatomical
## hurtbox components used by the canonical playground. CharacterBody remains
## movement authority; animated Area3D shapes remain damage-only geometry.

const MannequinScript := preload("res://scripts/player/test_mannequin.gd")
const AnimatedHurtboxRigScript := preload("res://scripts/combat/socom_animated_hurtbox_rig.gd")

signal eliminated(victim_peer_id: int, attacker_peer_id: int)

var network_peer_id: int = 0
var team_id: int = 0
var display_name: String = "OPERATOR"
var max_health: float = 100.0
var current_health: float = 100.0
var alive: bool = true
var mannequin: SocomTestMannequin
var hurtbox_rig: SocomAnimatedHurtboxRig
var nameplate: Label3D


var snapshot_history: Array[Dictionary] = []
var interpolation_delay_seconds: float = 0.130
var is_proxy_replica: bool = false


func _ready() -> void:
	_ensure_movement_collider()
	_ensure_operator_visual()
	_build_nameplate()
	call_deferred("_bind_animated_hurtboxes")


func _physics_process(delta: float) -> void:
	if not alive:
		velocity = Vector3.ZERO
		return
	if is_proxy_replica:
		# Proxy replicas are driven smoothly by snapshot interpolation in _process.
		# CharacterBody physics step does not simulate movement commands for proxies.
		return
	super(delta)


func configure_identity(peer_id: int, assigned_team: int) -> void:
	network_peer_id = peer_id
	team_id = assigned_team
	display_name = "SEAL %d" % peer_id
	if nameplate:
		_refresh_nameplate()


func set_replica_mode(enabled: bool) -> void:
	is_proxy_replica = enabled
	replay_override_active = enabled
	set_local_input_enabled(not enabled)


func push_network_snapshot(
	position_value: Vector3,
	yaw_value: float,
	velocity_value: Vector3,
	posture_value: int,
	health_value: float,
	alive_value: bool,
	timestamp_seconds: float
) -> void:
	var entry := {
		"time": timestamp_seconds,
		"position": position_value,
		"yaw": yaw_value,
		"velocity": velocity_value,
		"posture": posture_value,
		"health": health_value,
		"alive": alive_value,
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
	_apply_posture_collider()

	var blended_health := lerpf(float(s0["health"]), float(s1["health"]), alpha)
	var blended_alive := bool(s1["alive"]) if alpha >= 0.5 else bool(s0["alive"])
	_set_alive_and_health(blended_alive, blended_health)


func set_authoritative_snapshot(
	position_value: Vector3,
	yaw_value: float,
	velocity_value: Vector3,
	posture_value: int,
	health_value: float,
	alive_value: bool,
	hard_snap: bool = false
) -> void:
	if hard_snap or global_position.distance_to(position_value) > 1.25:
		global_position = position_value
	else:
		global_position = global_position.lerp(position_value, 0.28)
	rotation.y = lerp_angle(rotation.y, yaw_value, 0.40)
	velocity = velocity_value
	posture = clampi(posture_value, MotionState.STANDING, MotionState.PRONE)
	motion_state = posture
	_apply_posture_collider()
	_set_alive_and_health(alive_value, health_value)


func respawn_at(spawn_position: Vector3) -> void:
	snapshot_history.clear()
	global_position = spawn_position
	velocity = Vector3.ZERO
	posture = MotionState.STANDING
	motion_state = MotionState.STANDING
	_apply_posture_collider()
	_set_alive_and_health(true, max_health)


func take_bullet_damage_region(
	base_damage: float,
	hit_region: StringName,
	_hit_position: Vector3,
	_hit_normal: Vector3,
	_shooter_origin: Vector3 = Vector3.ZERO,
	attacker_peer_id: int = 0
) -> Dictionary:
	if not multiplayer.is_server() or not alive:
		return {"accepted": false, "hit_region": hit_region}
	var region := String(hit_region)
	var multiplier := 1.0
	if region == "HEAD":
		multiplier = 2.45
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


func _set_alive_and_health(value: bool, health_value: float) -> void:
	alive = value
	current_health = clampf(health_value, 0.0, max_health)
	collision_layer = 1 if alive else 0
	if mannequin:
		mannequin.visible = alive
	if hurtbox_rig:
		hurtbox_rig.set_enabled(alive)
	_refresh_nameplate()


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
	add_child(nameplate)
	_refresh_nameplate()


func _refresh_nameplate() -> void:
	if nameplate == null:
		return
	nameplate.text = (
		"%s  %.0f HP" % [display_name, current_health]
		if alive
		else "%s  ELIMINATED" % display_name
	)
	nameplate.modulate = (
		Color(0.35, 0.82, 1.0)
		if team_id == 0
		else Color(1.0, 0.45, 0.32)
	)


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
