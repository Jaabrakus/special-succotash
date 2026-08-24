class_name SocomWeaponController
extends Node

## Local lab adapter for a future server-authoritative weapon channel.
## Camera placement never crosses this boundary. Each shot carries sequenced
## aim intent; authority validates it, then deterministic server dispersion is
## applied from the authoritative muzzle.

const Ballistics := preload("res://scripts/weapons/weapon_ballistics.gd")
const ShotAuthority := preload("res://scripts/network/socom_shot_authority.gd")
const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const Composure := preload("res://scripts/weapons/operator_composure.gd")

signal authoritative_shot(result: Dictionary)
signal ammo_changed(rounds_in_magazine: int, reserve_rounds: int)
signal weapon_equipped(result: Dictionary)

var player: CharacterBody3D
var camera_rig
var mannequin
var ballistics
var input_enabled: bool = true
var last_accepted_sequence: int = -1
var last_result: Dictionary = {}
var composure = Composure.new()
var composure_profile: Dictionary = {}
var magazine_capacity: int = 30
var rounds_in_magazine: int = 30
var reserve_rounds: int = 90
var equipped_weapon_id: StringName = &"rifle"
var equipped_weapon_display_name: String = "Rifle"
var equipped_weapon_config: Dictionary = {}
var _movement_ratio: float = 0.0
var _turning_ratio: float = 0.0
var _last_camera_yaw: float = 0.0
var reticle_profile: Dictionary = {
	"base_gap_px": 10.0,
	"max_gap_px": 46.0,
	"response_speed": 24.0,
	"shot_kick_px": 0.0,
	"shot_kick_return": 18.0,
	"maximum_shot_kick_px": 0.0,
	"maximum_movement_tick_extension_px": 16.0,
}


func configure(target_player: CharacterBody3D, target_camera) -> void:
	player = target_player
	camera_rig = target_camera
	mannequin = player.get_node_or_null("Mannequin") if player != null else null
	ballistics = Ballistics.new()
	ballistics.name = "WeaponBallistics"
	add_child(ballistics)
	_apply_equipped_ballistics()
	rounds_in_magazine = magazine_capacity
	ammo_changed.emit(rounds_in_magazine, reserve_rounds)
	_last_camera_yaw = float(camera_rig.yaw) if camera_rig != null else 0.0


func _apply_equipped_ballistics() -> void:
	if ballistics == null:
		return
	var config := WeaponContract.load_equipped_config()
	_apply_weapon_config(config)


func _apply_weapon_config(config: Dictionary) -> bool:
	if ballistics == null or config.is_empty():
		return false
	equipped_weapon_config = config.duplicate(true)
	equipped_weapon_id = StringName(config.get("weapon_id", "rifle"))
	equipped_weapon_display_name = String(
		config.get("display_name", equipped_weapon_id)
	).replace("_", " ").strip_edges()
	if equipped_weapon_display_name.is_empty():
		equipped_weapon_display_name = String(equipped_weapon_id).replace("_", " ")
	var values: Dictionary = config.get("ballistics", {})
	var saved_reticle: Variant = config.get("reticle", {})
	if saved_reticle is Dictionary:
		reticle_profile.merge((saved_reticle as Dictionary), true)
	reticle_profile["functional_aim_climb_enabled"] = bool(
		values.get("functional_aim_climb_enabled", false)
	)
	if camera_rig != null and camera_rig.has_method("configure_functional_aim_climb"):
		camera_rig.call("configure_functional_aim_climb", values)
	var saved_composure: Variant = config.get("composure", {})
	if saved_composure is Dictionary:
		composure_profile = (saved_composure as Dictionary).duplicate(true)
		composure.configure_weapon(composure_profile)
	ballistics.fire_rate_rpm = float(values.get("fire_rate_rpm", ballistics.fire_rate_rpm))
	ballistics.damage_per_shot = float(values.get("damage", ballistics.damage_per_shot))
	ballistics.headshot_multiplier = clampf(
		float(values.get("headshot_multiplier", ballistics.headshot_multiplier)),
		1.0,
		10.0
	)
	ballistics.muzzle_velocity_mps = float(values.get("muzzle_velocity_mps", ballistics.muzzle_velocity_mps))
	ballistics.base_spread_deg = float(values.get("base_spread_deg", ballistics.base_spread_deg))
	ballistics.moving_spread_deg = float(values.get("moving_spread_deg", ballistics.moving_spread_deg))
	ballistics.full_gait_spread_deg = float(values.get("full_gait_spread_deg", ballistics.full_gait_spread_deg))
	ballistics.opening_burst_motion_multiplier = float(values.get(
		"opening_burst_motion_multiplier",
		ballistics.opening_burst_motion_multiplier
	))
	ballistics.bloom_per_shot_deg = float(values.get("bloom_per_shot_deg", ballistics.bloom_per_shot_deg))
	ballistics.max_recoil_bloom_deg = float(values.get("max_recoil_bloom_deg", ballistics.max_recoil_bloom_deg))
	ballistics.bloom_recovery_speed = float(values.get("bloom_recovery_speed", ballistics.bloom_recovery_speed))
	ballistics.crouch_spread_multiplier = float(values.get("crouch_spread_multiplier", ballistics.crouch_spread_multiplier))
	ballistics.crouch_bloom_per_shot_deg = float(values.get("crouch_bloom_per_shot_deg", ballistics.crouch_bloom_per_shot_deg))
	ballistics.crouch_max_recoil_bloom_deg = float(values.get("crouch_max_recoil_bloom_deg", ballistics.crouch_max_recoil_bloom_deg))
	ballistics.crouch_bloom_recovery_speed = float(values.get("crouch_bloom_recovery_speed", ballistics.crouch_bloom_recovery_speed))
	magazine_capacity = clampi(int(values.get("magazine_capacity", magazine_capacity)), 1, 200)
	reserve_rounds = clampi(int(values.get("reserve_ammo", reserve_rounds)), 0, 999)
	ballistics.fire_interval = 60.0 / maxf(60.0, ballistics.fire_rate_rpm)
	return true


func apply_authorized_weapon_pickup(config_path: String) -> bool:
	# This is the post-validation handoff. Network/server code must approve the
	# pickup before it reaches this method; animation never grants equipment.
	if (
		not config_path.begins_with("res://config/weapons/")
		or not config_path.ends_with(".json")
	):
		return false
	var config := WeaponContract.load_config(config_path)
	if config.is_empty() or mannequin == null:
		return false
	if (
		not mannequin.has_method("notify_operator_weapon_equipped")
		or not bool(mannequin.call("notify_operator_weapon_equipped", config))
	):
		return false
	if not _apply_weapon_config(config):
		return false
	rounds_in_magazine = magazine_capacity
	ammo_changed.emit(rounds_in_magazine, reserve_rounds)
	var handling: Dictionary = config.get("handling_profile", {})
	weapon_equipped.emit({
		"event": "WEAPON_EQUIPPED",
		"weapon_id": String(equipped_weapon_id),
		"family": String(handling.get("family", "")),
		"config_path": config_path,
	})
	return true


func _physics_process(delta: float) -> void:
	if player == null or camera_rig == null:
		return
	var horizontal_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var maximum_speed := maxf(float(player.get("move_speed")), 0.001)
	_movement_ratio = clampf(horizontal_speed / maximum_speed, 0.0, 1.0)
	var current_yaw := float(camera_rig.yaw)
	var yaw_speed := absf(angle_difference(_last_camera_yaw, current_yaw)) / maxf(delta, 0.0001)
	_turning_ratio = clampf(yaw_speed / deg_to_rad(180.0), 0.0, 1.0)
	_last_camera_yaw = current_yaw
	var posture_name: StringName = (
		StringName(player.call("get_posture_name"))
		if player.has_method("get_posture_name")
		else &"STANDING"
	)
	var stance := OperatorComposure.Stance.STANDING
	if posture_name == &"CROUCHED":
		stance = OperatorComposure.Stance.CROUCHED
	elif posture_name == &"PRONE":
		stance = OperatorComposure.Stance.PRONE
	composure.advance(delta, _movement_ratio, _turning_ratio, stance)
	var retained_instability := composure.get_shot_instability(
		_movement_ratio,
		_turning_ratio
	)
	ballistics.update_spread_state(
		posture_name,
		retained_instability,
		not player.is_on_floor()
	)
	if camera_rig.has_method("set_weapon_aim_instability"):
		# The higher of locomotion or live reticle bloom drives only the local
		# mouse-string envelope. It never changes the authoritative shot result.
		camera_rig.call(
			"set_weapon_aim_instability",
			maxf(_movement_ratio, get_reticle_spread_normalized())
		)


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
	if rounds_in_magazine <= 0:
		ballistics.release_trigger()
		return {"fired": false, "reason": "MAGAZINE_EMPTY"}

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

	var posture_name: StringName = (
		StringName(player.call("get_posture_name"))
		if player.has_method("get_posture_name")
		else &"STANDING"
	)
	var seed: int = int(payload.sequence) * 73856093 ^ int(payload.simulation_tick) * 19349663
	var exclude: Array[RID] = [player.get_rid()]
	var next_shot_in_burst := int(ballistics.continuous_shot_count) + 1
	var retained_instability := composure.get_shot_instability(
		_movement_ratio,
		_turning_ratio
	)
	var dispersion_multiplier := composure.get_shot_dispersion_multiplier(
		next_shot_in_burst,
		_movement_ratio,
		_turning_ratio
	)
	# Snapshot the current composure before recoil stress is added. The shot that
	# was just triggered must use the stability the operator had at trigger time;
	# the new stress affects the following shot.
	var shot_precision_core_scale := composure.get_precision_core_scale()
	var result: Dictionary = ballistics.try_fire_direction(
		muzzle,
		Vector3(validation.direction),
		player.get_world_3d().direct_space_state,
		exclude,
		seed,
		posture_name,
		retained_instability,
		not player.is_on_floor(),
		dispersion_multiplier
	)
	if not bool(result.get("fired", false)):
		return result
	rounds_in_magazine = maxi(0, rounds_in_magazine - 1)
	result["rounds_in_magazine"] = rounds_in_magazine
	result["reserve_ammo"] = reserve_rounds
	ammo_changed.emit(rounds_in_magazine, reserve_rounds)
	var opening_stress_multiplier := float(
		composure_profile.get("opening_stress_multiplier", 0.28)
		if next_shot_in_burst <= 2
		else 1.0
	)
	composure.notify_shot(1.0, opening_stress_multiplier)
	result["composure"] = composure.get_composure()
	result["precision_core_scale"] = shot_precision_core_scale
	result["reticle_bounce"] = composure.get_shot_bounce_impulse()
	var rendered_barrel_direction := (
		Vector3(mannequin.get_active_barrel_direction())
		if mannequin.has_method("get_active_barrel_direction")
		else Vector3(validation.direction)
	)
	result["rendered_barrel_direction"] = rendered_barrel_direction
	result["aim_center_direction"] = Vector3(validation.direction)
	result["aim_center_point"] = (
		Vector3(camera_rig.call("get_shared_aim_target"))
		if camera_rig.has_method("get_shared_aim_target")
		else muzzle + Vector3(validation.direction) * 100.0
	)
	result["barrel_alignment_error_deg"] = rad_to_deg(
		rendered_barrel_direction.angle_to(Vector3(validation.direction))
	)
	if camera_rig.has_method("notify_functional_aim_climb"):
		camera_rig.call("notify_functional_aim_climb", next_shot_in_burst)
		result["functional_aim_climb"] = camera_rig.call(
			"get_functional_aim_climb_debug_state"
		)

	last_accepted_sequence = int(payload.sequence)
	result["origin"] = muzzle
	result["sequence"] = last_accepted_sequence
	result["simulation_tick"] = int(payload.simulation_tick)
	last_result = result
	var hit_collider: Object = result.get("hit_collider")
	if hit_collider != null and hit_collider.has_method("take_bullet_damage"):
		var damage_classification := {
			"precision": true,
			"graze": false,
			"normalized_radius": 0.0,
			"precision_core_scale": shot_precision_core_scale,
		}
		if hit_collider.has_method("classify_shot_path"):
			damage_classification = hit_collider.call(
				"classify_shot_path",
				muzzle,
				Vector3(result.direction),
				shot_precision_core_scale
			)
		var damage_scale := 1.0
		if not bool(damage_classification.get("precision", true)):
			damage_classification["graze"] = true
			damage_scale = clampf(
				float(composure_profile.get("graze_damage_scale", 0.38)),
				0.0,
				1.0
			)
		result["damage_classification"] = damage_classification
		result["damage_scale"] = damage_scale
		result["damage_result"] = hit_collider.call(
			"take_bullet_damage",
			float(ballistics.damage_per_shot) * damage_scale,
			Vector3(result.hit_pos),
			Vector3(result.get("normal", Vector3.UP)),
			player.global_position,
			float(ballistics.headshot_multiplier)
		)
	camera_rig.last_fired_direction = Vector3(result.direction)
	camera_rig.last_fired_point = Vector3(result.hit_pos)
	camera_rig.last_fired_tick = Engine.get_physics_frames()
	camera_rig.last_fired_spread_deg = float(result.spread_deg)
	if mannequin.has_method("notify_operator_fired"):
		mannequin.call("notify_operator_fired")
	authoritative_shot.emit(result)
	return result


func request_reload() -> bool:
	if rounds_in_magazine >= magazine_capacity or reserve_rounds <= 0:
		# Keep the authored reload preview available even when the magazine is full.
		return true
	var needed := magazine_capacity - rounds_in_magazine
	var transferred := mini(needed, reserve_rounds)
	rounds_in_magazine += transferred
	reserve_rounds -= transferred
	ballistics.release_trigger()
	ammo_changed.emit(rounds_in_magazine, reserve_rounds)
	return transferred > 0


func get_ammo_snapshot() -> Dictionary:
	return {
		"weapon_id": equipped_weapon_id,
		"display_name": equipped_weapon_display_name,
		"magazine_capacity": magazine_capacity,
		"rounds_in_magazine": rounds_in_magazine,
		"reserve_ammo": reserve_rounds,
	}


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled and ballistics != null:
		ballistics.release_trigger()


func get_reticle_spread_normalized() -> float:
	var ballistic_spread := 0.0
	if ballistics != null:
		ballistic_spread = ballistics.get_normalized_spread()
	return maxf(ballistic_spread, composure.get_visual_bloom())


func get_movement_ratio() -> float:
	return _movement_ratio
