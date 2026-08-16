class_name SocomAimIntent
extends RefCounted

static func create(
    new_sequence: int,
    new_tick: int,
    new_yaw: float,
    new_pitch: float,
    muzzle_origin: Vector3,
    aim_direction: Vector3
) -> Dictionary:
    return {
        "sequence": new_sequence,
        "simulation_tick": new_tick,
        "yaw": new_yaw,
        "pitch": new_pitch,
        "reported_muzzle_origin": muzzle_origin,
        "direction": aim_direction.normalized()
    }


static func is_sane(
    payload: Dictionary,
    authoritative_muzzle_origin: Vector3,
    origin_tolerance: float = 0.75
) -> bool:
    var direction: Vector3 = payload.get("direction", Vector3.ZERO)
    var reported_origin: Vector3 = payload.get(
        "reported_muzzle_origin",
        authoritative_muzzle_origin
    )
    return (
        direction.is_finite()
        and absf(direction.length() - 1.0) <= 0.01
        and reported_origin.distance_to(authoritative_muzzle_origin)
            <= origin_tolerance
    )
