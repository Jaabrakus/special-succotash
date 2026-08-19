class_name OperatorComposure
extends RefCounted

## Deterministic shooter-owned stability state.
##
## `stress` is authoritative gameplay state. `visual_stress` is a damped
## presentation spring that lets the reticle breathe without changing shot
## validation. Enemy geometry never mutates; a shot can derive its temporary
## precision-core scale from the shooter's authoritative stress.

enum Stance {
	STANDING,
	CROUCHED,
	PRONE,
}

var stress: float = 0.0
var visual_stress: float = 0.0
var visual_velocity: float = 0.0
var shot_bounce_age: float = 99.0
var shot_bounce_duration: float = 0.070
var shot_bounce_strength: float = 1.0

var shot_stress: float = 0.085
var movement_stress: float = 0.58
var turning_stress: float = 0.34
var stress_attack_speed: float = 4.8
var recovery_speed: float = 1.45
var minimum_core_scale: float = 0.70
var visual_spring: float = 72.0
var visual_damping: float = 13.5
var settled_first_shot_threshold: float = 0.035
var settled_motion_threshold: float = 0.08
var moving_first_shot_multiplier: float = 0.42
var second_shot_multiplier: float = 0.18


func reset() -> void:
	stress = 0.0
	visual_stress = 0.0
	visual_velocity = 0.0
	shot_bounce_age = 99.0
	shot_bounce_strength = 1.0


func configure_weapon(profile: Dictionary) -> void:
	shot_stress = float(profile.get("shot_stress", shot_stress))
	movement_stress = float(profile.get("movement_stress", movement_stress))
	turning_stress = float(profile.get("turning_stress", turning_stress))
	stress_attack_speed = float(profile.get("stress_attack_speed", stress_attack_speed))
	recovery_speed = float(profile.get("recovery_speed", recovery_speed))
	minimum_core_scale = float(profile.get("minimum_core_scale", minimum_core_scale))
	visual_spring = float(profile.get("visual_spring", visual_spring))
	visual_damping = float(profile.get("visual_damping", visual_damping))
	shot_bounce_duration = float(profile.get("bounce_duration", shot_bounce_duration))
	shot_bounce_strength = float(profile.get("bounce_strength", shot_bounce_strength))
	settled_first_shot_threshold = float(
		profile.get("settled_first_shot_threshold", settled_first_shot_threshold)
	)
	settled_motion_threshold = float(
		profile.get("settled_motion_threshold", settled_motion_threshold)
	)
	moving_first_shot_multiplier = float(
		profile.get("moving_first_shot_multiplier", moving_first_shot_multiplier)
	)
	second_shot_multiplier = float(
		profile.get("second_shot_multiplier", second_shot_multiplier)
	)


func export_profile() -> Dictionary:
	return {
		"shot_stress": shot_stress,
		"movement_stress": movement_stress,
		"turning_stress": turning_stress,
		"stress_attack_speed": stress_attack_speed,
		"recovery_speed": recovery_speed,
		"minimum_core_scale": minimum_core_scale,
		"visual_spring": visual_spring,
		"visual_damping": visual_damping,
		"bounce_duration": shot_bounce_duration,
		"bounce_strength": shot_bounce_strength,
		"settled_first_shot_threshold": settled_first_shot_threshold,
		"settled_motion_threshold": settled_motion_threshold,
		"moving_first_shot_multiplier": moving_first_shot_multiplier,
		"second_shot_multiplier": second_shot_multiplier,
	}


func notify_shot(intensity: float = 1.0, stress_multiplier: float = 1.0) -> void:
	var impulse := clampf(intensity, 0.25, 2.0)
	var gameplay_stress := clampf(stress_multiplier, 0.0, 2.0)
	stress = clampf(stress + shot_stress * impulse * gameplay_stress, 0.0, 1.0)
	visual_velocity += 1.55 * impulse
	shot_bounce_age = 0.0


func advance(
	delta: float,
	movement_amount: float,
	turning_amount: float,
	stance: Stance = Stance.STANDING
) -> void:
	var movement_floor := clampf(movement_amount, 0.0, 1.0) * movement_stress
	var turning_floor := clampf(turning_amount, 0.0, 1.0) * turning_stress
	var stress_floor := maxf(movement_floor, turning_floor)
	var stance_recovery := 1.0
	match stance:
		Stance.CROUCHED:
			stance_recovery = 1.28
		Stance.PRONE:
			stance_recovery = 1.62

	if stress < stress_floor:
		stress = move_toward(stress, stress_floor, stress_attack_speed * delta)
	else:
		stress = move_toward(
			stress,
			stress_floor,
			recovery_speed * stance_recovery * delta
		)

	# A tiny critically-near-damped spring produces one organic compression
	# and release after stress changes, then becomes completely still at rest.
	var acceleration := (
		(stress - visual_stress) * visual_spring
		- visual_velocity * visual_damping
	)
	visual_velocity += acceleration * delta
	visual_stress = clampf(visual_stress + visual_velocity * delta, 0.0, 1.0)
	shot_bounce_age += delta


func get_composure() -> float:
	return 1.0 - stress


func get_visual_bloom() -> float:
	return visual_stress


func get_precision_core_scale() -> float:
	return lerpf(1.0, minimum_core_scale, pow(stress, 1.20))


func get_shot_dispersion_multiplier(
	shot_number_in_burst: int,
	movement_amount: float,
	turning_amount: float
) -> float:
	# A trained, settled operator owns the exact first shot. Recoil presentation
	# is applied after this value is read and therefore only informs later shots.
	if shot_number_in_burst <= 1:
		var settled := (
			stress <= settled_first_shot_threshold
			and movement_amount <= settled_motion_threshold
			and turning_amount <= settled_motion_threshold
		)
		return 0.0 if settled else moving_first_shot_multiplier
	if shot_number_in_burst == 2:
		return second_shot_multiplier
	return 1.0


func get_shot_bounce() -> float:
	var phase := shot_bounce_age / maxf(shot_bounce_duration, 0.001)
	if phase >= 1.0:
		return 0.0
	# Very fast attack, short crown, smooth trained return. Every accepted shot
	# restarts this envelope instead of accumulating an endless upward climb.
	var pulse: float
	if phase < 0.16:
		pulse = smoothstep(0.0, 0.16, phase)
	elif phase < 0.38:
		pulse = lerpf(1.0, 0.88, (phase - 0.16) / 0.22)
	else:
		pulse = 0.88 * (1.0 - smoothstep(0.38, 1.0, phase))
	return pulse * shot_bounce_strength


func get_shot_bounce_impulse() -> float:
	return shot_bounce_strength
