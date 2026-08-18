class_name SocomWeaponController
extends Node

## Local lab adapter for a future server-authoritative weapon channel.
## Camera placement never crosses this boundary. Each shot carries sequenced
## aim intent; authority validates it, then deterministic server dispersion is
## applied from the authoritative muzzle.

const Ballistics := preload("res://scripts/weapons/weapon_ballistics.gd")
const ShotAuthority := preload("res://scripts/network/socom_shot_authority.gd")

signal authoritative_shot(result: Dictionary)

var player: CharacterBody3D
var camera_rig
var mannequin
var ballistics
var input_enabled: bool = true
var last_accepted_sequence: int = -1
var last_result: Dictionary = {}


func configure(target_player: CharacterBody3D, target_camera) -> void:
	player = target_player
	camera_rig = target_camera
	mannequin = player.get_node_or_null("Mannequin") if player != null else null
	ballistics = Ballistics.new()
	ballistics.name = "WeaponBallistics"
	add_child(ballistics)


func _process(_delta: float) -> void:
	if ballistics == null:
		return
	var local_fire_allowed := (
		input_enabled
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and not OS.get_cmdline_user_args().has("--automated-test")
	)
	if local_fire_allowed and Input.is_action_pressed("fire"):
		request_fire()
	else:
		ballistics.release_trigger()


func request_fire() -> Dictionary:
	if (
		ballistics == null
		or player == null
		or camera_rig == null
		or mannequin == null
		or mannequin.muzzle_marker == null
	):
		return {"fired": false, "reason": "WEAPON_NOT_READY"}

	var muzzle: Vector3 = mannequin.muzzle_marker.global_position
	var payload: Dictionary = camera_rig.build_local_aim_intent()
	var validation: Dictionary = ShotAuthority.validate_intent(
		payload,
		muzzle,
		last_accepted_sequence,
		Engine.get_physics_frames()
	)
	if not bool(validation.get("accepted", false)):
		return {"fired": false, "reason": validation.get("reason", "REJECTED")}

	var horizontal_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var maximum_speed := maxf(float(player.get("move_speed")), 0.001)
	var movement_ratio := clampf(horizontal_speed / maximum_speed, 0.0, 1.0)
	var posture_name: StringName = (
		StringName(player.call("get_posture_name"))
		if player.has_method("get_posture_name")
		else &"STANDING"
	)
	var seed: int = int(payload.sequence) * 73856093 ^ int(payload.simulation_tick) * 19349663
	var exclude: Array[RID] = [player.get_rid()]
	var result: Dictionary = ballistics.try_fire_direction(
		muzzle,
		Vector3(validation.direction),
		player.get_world_3d().direct_space_state,
		exclude,
		seed,
		posture_name,
		movement_ratio,
		not player.is_on_floor()
	)
	if not bool(result.get("fired", false)):
		return result

	last_accepted_sequence = int(payload.sequence)
	result["sequence"] = last_accepted_sequence
	result["simulation_tick"] = int(payload.simulation_tick)
	last_result = result
	camera_rig.last_fired_direction = Vector3(result.direction)
	camera_rig.last_fired_point = Vector3(result.hit_pos)
	camera_rig.last_fired_tick = Engine.get_physics_frames()
	camera_rig.last_fired_spread_deg = float(result.spread_deg)
	if mannequin.has_method("notify_operator_fired"):
		mannequin.call("notify_operator_fired")
	authoritative_shot.emit(result)
	return result


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled and ballistics != null:
		ballistics.release_trigger()
