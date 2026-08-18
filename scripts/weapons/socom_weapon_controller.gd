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
var reticle_profile: Dictionary = {
	"base_gap_px": 10.0,
	"max_gap_px": 46.0,
	"response_speed": 24.0,
	"shot_kick_px": 6.0,
	"shot_kick_return": 18.0,
	"maximum_shot_kick_px": 18.0,
}


func configure(target_player: CharacterBody3D, target_camera) -> void:
	player = target_player
	camera_rig = target_camera
	mannequin = player.get_node_or_null("Mannequin") if player != null else null
	ballistics = Ballistics.new()
	ballistics.name = "WeaponBallistics"
	add_child(ballistics)
	_apply_equipped_ballistics()


func _apply_equipped_ballistics() -> void:
	var loadout_path := "res://config/weapons/operator_loadout.json"
	if ballistics == null:
		return
	var config_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--weapon-rig-config="):
			config_path = argument.trim_prefix("--weapon-rig-config=")
			break
	if config_path == "":
		if not FileAccess.file_exists(loadout_path):
			return
		var loadout_file := FileAccess.open(loadout_path, FileAccess.READ)
		var loadout_value: Variant = (
			JSON.parse_string(loadout_file.get_as_text())
			if loadout_file != null
			else null
		)
		if not loadout_value is Dictionary:
			return
		config_path = String((loadout_value as Dictionary).get("rig_config", ""))
	if config_path == "" or not FileAccess.file_exists(config_path):
		return
	var config_file := FileAccess.open(config_path, FileAccess.READ)
	var config_value: Variant = (
		JSON.parse_string(config_file.get_as_text())
		if config_file != null
		else null
	)
	if not config_value is Dictionary:
		return
	var values: Dictionary = (config_value as Dictionary).get("ballistics", {})
	var saved_reticle: Variant = (config_value as Dictionary).get("reticle", {})
	if saved_reticle is Dictionary:
		reticle_profile.merge((saved_reticle as Dictionary), true)
	ballistics.fire_rate_rpm = float(values.get("fire_rate_rpm", ballistics.fire_rate_rpm))
	ballistics.damage_per_shot = float(values.get("damage", ballistics.damage_per_shot))
	ballistics.base_spread_deg = float(values.get("base_spread_deg", ballistics.base_spread_deg))
	ballistics.bloom_per_shot_deg = float(values.get("bloom_per_shot_deg", ballistics.bloom_per_shot_deg))
	ballistics.max_recoil_bloom_deg = float(values.get("max_recoil_bloom_deg", ballistics.max_recoil_bloom_deg))
	ballistics.bloom_recovery_speed = float(values.get("bloom_recovery_speed", ballistics.bloom_recovery_speed))
	ballistics.fire_interval = 60.0 / maxf(60.0, ballistics.fire_rate_rpm)


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
	):
		return {"fired": false, "reason": "WEAPON_NOT_READY"}

	var active_muzzle: Node3D = (
		mannequin.get_active_muzzle_marker()
		if mannequin.has_method("get_active_muzzle_marker")
		else mannequin.muzzle_marker
	)
	if active_muzzle == null:
		return {"fired": false, "reason": "WEAPON_NOT_READY"}
	var muzzle: Vector3 = active_muzzle.global_position
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
	result["origin"] = muzzle
	result["sequence"] = last_accepted_sequence
	result["simulation_tick"] = int(payload.simulation_tick)
	last_result = result
	var hit_collider: Object = result.get("hit_collider")
	if hit_collider != null and hit_collider.has_method("take_bullet_damage"):
		result["damage_result"] = hit_collider.call(
			"take_bullet_damage",
			float(ballistics.damage_per_shot),
			Vector3(result.hit_pos),
			Vector3(result.get("normal", Vector3.UP)),
			player.global_position
		)
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
