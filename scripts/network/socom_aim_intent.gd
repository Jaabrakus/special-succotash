class_name SocomAimIntent
extends RefCounted

var sequence: int
var simulation_tick: int
var yaw: float
var pitch: float
var reported_muzzle_origin: Vector3
var direction: Vector3


static func create(
    new_sequence: int,
    new_tick: int,
    new_yaw: float,
    new_pitch: float,
    muzzle_origin: Vector3,
    aim_direction: Vector3
) -> SocomAimIntent:
    var intent := SocomAimIntent.new()
    intent.sequence = new_sequence
    intent.simulation_tick = new_tick
    intent.yaw = new_yaw
    intent.pitch = new_pitch
    intent.reported_muzzle_origin = muzzle_origin
    intent.direction = aim_direction.normalized()
    return intent


func to_payload() -> Dictionary:
    return {
        "sequence": sequence,
        "simulation_tick": simulation_tick,
        "yaw": yaw,
        "pitch": pitch,
        "reported_muzzle_origin": reported_muzzle_origin,
        "direction": direction
    }


func is_sane(authoritative_muzzle_origin: Vector3, origin_tolerance: float = 0.75) -> bool:
    return (
        direction.is_finite()
        and absf(direction.length() - 1.0) <= 0.01
        and reported_muzzle_origin.distance_to(authoritative_muzzle_origin)
            <= origin_tolerance
    )
