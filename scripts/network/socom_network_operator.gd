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


func _ready() -> void:
	_ensure_movement_collider()
	_ensure_operator_visual()
	_build_nameplate()
	call_deferred("_bind_animated_hurtboxes")


func _physics_process(delta: float) -> void:
	if not alive:
		velocity = Vector3.ZERO
		return
	super(delta)


func configure_identity(peer_id: int, assigned_team: int) -> void:
	network_peer_id = peer_id
	team_id = assigned_team
	display_name = "SEAL %d" % peer_id
	if nameplate:
		_refresh_nameplate()


func set_replica_mode(enabled: bool) -> void:
	replay_override_active = enabled
	set_local_input_enabled(not enabled)


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
	elif "ARM" in region or "THIGH" in region or "CALF" in region or "FOOT" in region:
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
