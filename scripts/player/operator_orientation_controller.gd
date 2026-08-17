class_name SocomOperatorOrientationController
extends RefCounted

## Keeps locomotion heading and aim heading as two separate authorities.
##
## Movement owns travel only. Mouse/right-stick aim is never rewritten here.
## The root remains planted until the upper body reaches its anatomical yaw
## limit, then the lower body catches up without changing the aim heading.

var movement_direction := Vector3.ZERO
var aim_relative_yaw: float = 0.0
var is_turning_in_place: bool = false


func update(
    player: CharacterBody3D,
    desired_direction: Vector3,
    authoritative_aim_yaw: float,
    delta: float,
    movement_turn_response: float,
    idle_turn_response: float,
    torso_yaw_limit: float
) -> void:
    movement_direction = desired_direction
    movement_direction.y = 0.0
    var is_moving := movement_direction.length_squared() > 0.001
    if is_moving:
        movement_direction = movement_direction.normalized()
    var yaw_error := wrapf(authoritative_aim_yaw - player.global_rotation.y, -PI, PI)
    if absf(yaw_error) > torso_yaw_limit:
        var permitted_twist := signf(yaw_error) * torso_yaw_limit
        var catchup_yaw := player.rotation.y + yaw_error - permitted_twist
        var response := movement_turn_response if is_moving else idle_turn_response
        player.rotation.y = lerp_angle(
            player.rotation.y,
            catchup_yaw,
            1.0 - exp(-response * delta)
        )
        is_turning_in_place = not is_moving
    else:
        is_turning_in_place = false

    aim_relative_yaw = wrapf(authoritative_aim_yaw - player.global_rotation.y, -PI, PI)


func reset(player: CharacterBody3D, authoritative_aim_yaw: float) -> void:
    movement_direction = Vector3.ZERO
    aim_relative_yaw = wrapf(authoritative_aim_yaw - player.global_rotation.y, -PI, PI)
    is_turning_in_place = false
