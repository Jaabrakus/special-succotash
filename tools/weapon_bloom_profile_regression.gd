extends SceneTree

const Ballistics := preload("res://scripts/weapons/weapon_ballistics.gd")
const DynamicReticle := preload("res://scripts/ui/socom_dynamic_reticle.gd")
const PROFILE_PATH := "res://config/weapons/assaultrifle_1.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var profile := _load_profile()
	var values: Dictionary = profile.get("ballistics", {})
	var reticle: Dictionary = profile.get("reticle", {})

	_expect(is_equal_approx(float(values.get("moving_spread_deg", -1.0)), 0.95), "walk spread remains unchanged")
	_expect(is_equal_approx(float(values.get("full_gait_spread_deg", -1.0)), 1.45), "full strafe spread uses the approved cone")
	_expect(is_equal_approx(float(values.get("bloom_recovery_speed", -1.0)), 14.0), "standing settle timing remains unchanged")
	_expect(is_equal_approx(float(values.get("crouch_bloom_recovery_speed", -1.0)), 16.5), "crouch settle timing remains unchanged")
	_expect(is_equal_approx(float(reticle.get("max_gap_px", -1.0)), 46.0), "reticle maximum gap is bounded")
	_expect(is_equal_approx(float(reticle.get("shot_kick_px", -1.0)), 10.5), "reticle shot kick remains unchanged")
	var cadence_reticle := DynamicReticle.new()
	cadence_reticle.apply_profile(reticle.merged({
		"fire_interval_seconds": 60.0 / float(values.get("fire_rate_rpm", 60.0)),
	}, true))
	_expect(
		is_equal_approx(cadence_reticle.shot_bounce_duration, (60.0 / 435.0) * 0.52),
		"bounce duration follows the rifle cadence"
	)
	_expect(
		is_equal_approx(cadence_reticle.shot_kick_return, -log(0.10) / (60.0 / 435.0)),
		"kick return leaves ten percent before the next legal shot"
	)

	var arena := Node3D.new()
	root.add_child(arena)
	await process_frame
	await physics_frame

	var standing := Ballistics.new()
	var crouched := Ballistics.new()
	arena.add_child(standing)
	arena.add_child(crouched)
	_apply_profile(standing, values)
	_apply_profile(crouched, values)

	var standing_spreads := _fire_burst(standing, arena, &"STANDING", 6, 0.0)
	var crouched_spreads := _fire_burst(crouched, arena, &"CROUCHED", 6, 0.0)
	var moving_spreads := _fire_burst(_configured_ballistics(arena, values), arena, &"STANDING", 3, 1.0)

	_expect(is_equal_approx(standing_spreads[0], standing_spreads[1]), "settled opening pair shares one precise cone")
	_expect(standing_spreads[2] > standing_spreads[1], "standing bloom begins on the third shot")
	_expect(standing_spreads[4] <= 1.78, "standing sustained-fire cone stays bounded")
	_expect(crouched_spreads[2] < standing_spreads[2], "crouch produces a tighter controlled burst")
	_expect(crouched_spreads[3] < standing_spreads[3], "crouch reaches a smaller sustained-fire cone")
	_expect(moving_spreads[0] >= 1.75, "full strafe remains wider than settled fire")
	_expect(moving_spreads[2] > moving_spreads[1], "full-strafe spraying still blooms after the opening pair")
	cadence_reticle.free()
	arena.queue_free()
	await process_frame

	if failures.is_empty():
		print(
			"WEAPON_BLOOM_PROFILE_REGRESSION PASS standing=%s crouched=%s moving=%s"
			% [standing_spreads, crouched_spreads, moving_spreads]
		)
		quit(0)
		return
	for failure in failures:
		push_error("WEAPON_BLOOM_PROFILE_REGRESSION: %s" % failure)
	quit(1)


func _load_profile() -> Dictionary:
	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	_expect(file != null, "weapon profile opens")
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	_expect(parsed is Dictionary, "weapon profile parses")
	return parsed if parsed is Dictionary else {}


func _configured_ballistics(parent: Node3D, values: Dictionary):
	var ballistics := Ballistics.new()
	parent.add_child(ballistics)
	_apply_profile(ballistics, values)
	return ballistics


func _apply_profile(ballistics, values: Dictionary) -> void:
	ballistics.base_spread_deg = float(values.get("base_spread_deg", 0.0))
	ballistics.moving_spread_deg = float(values.get("moving_spread_deg", 0.0))
	ballistics.full_gait_spread_deg = float(values.get("full_gait_spread_deg", 0.0))
	ballistics.opening_burst_motion_multiplier = float(values.get("opening_burst_motion_multiplier", 1.0))
	ballistics.bloom_per_shot_deg = float(values.get("bloom_per_shot_deg", 0.0))
	ballistics.max_recoil_bloom_deg = float(values.get("max_recoil_bloom_deg", 0.0))
	ballistics.bloom_recovery_speed = float(values.get("bloom_recovery_speed", 0.0))
	ballistics.crouch_spread_multiplier = float(values.get("crouch_spread_multiplier", 1.0))
	ballistics.crouch_bloom_per_shot_deg = float(values.get("crouch_bloom_per_shot_deg", 0.0))
	ballistics.crouch_max_recoil_bloom_deg = float(values.get("crouch_max_recoil_bloom_deg", 0.0))
	ballistics.crouch_bloom_recovery_speed = float(values.get("crouch_bloom_recovery_speed", 0.0))


func _fire_burst(ballistics, arena: Node3D, posture: StringName, count: int, movement: float) -> Array[float]:
	var spreads: Array[float] = []
	var excluded_rids: Array[RID] = []
	for shot in count:
		ballistics.fire_cooldown = 0.0
		var result: Dictionary = ballistics.try_fire_direction(
			Vector3.ZERO,
			Vector3.FORWARD,
			arena.get_world_3d().direct_space_state,
			excluded_rids,
			1000 + shot,
			posture,
			movement,
			false,
			1.0
		)
		_expect(bool(result.get("fired", false)), "profile burst shot fires")
		spreads.append(float(result.get("spread_deg", -1.0)))
	return spreads


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("WEAPON_BLOOM_PROFILE_CHECK PASS ", label)
	else:
		failures.append(label)
