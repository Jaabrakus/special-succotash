class_name SocomSwimmingMotor
extends RefCounted

## Pure swimming velocity solver. It has no Node, camera, animation, or Input
## dependency, which keeps prediction/replay and unit tests deterministic.

var surface_speed: float = 3.8
var underwater_speed: float = 4.6
var vertical_speed: float = 3.0
var acceleration: float = 9.0
var braking: float = 6.0
var surface_response: float = 5.5
var surface_submersion: float = 0.72
var dive_depth_threshold: float = 1.05


func solve(
	current_velocity: Vector3,
	world_move_direction: Vector3,
	vertical_axis: float,
	body_height: float,
	water_surface_y: float,
	delta: float
) -> Dictionary:
	var safe_delta := maxf(delta, 0.0)
	var depth := water_surface_y - body_height
	var underwater := depth >= dive_depth_threshold or vertical_axis < -0.05
	var planar_direction := Vector3(
		world_move_direction.x,
		0.0,
		world_move_direction.z
	).limit_length(1.0)
	var target_speed := underwater_speed if underwater else surface_speed
	var target_velocity := planar_direction * target_speed

	if underwater:
		target_velocity.y = clampf(vertical_axis, -1.0, 1.0) * vertical_speed
	else:
		var target_height := water_surface_y - surface_submersion
		var surface_error := target_height - body_height
		target_velocity.y = clampf(
			surface_error * surface_response + maxf(vertical_axis, 0.0) * vertical_speed,
			-vertical_speed,
			vertical_speed
		)

	var response := acceleration if target_velocity.length_squared() > 0.001 else braking
	var solved_velocity := current_velocity.move_toward(
		target_velocity,
		response * safe_delta
	)
	return {
		"velocity": solved_velocity,
		"underwater": underwater,
		"depth": depth,
		"target_velocity": target_velocity,
	}
