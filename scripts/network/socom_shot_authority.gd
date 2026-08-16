class_name SocomShotAuthority
extends RefCounted


static func validate_and_trace(
    world: World3D,
    payload: Dictionary,
    authoritative_muzzle_origin: Vector3,
    exclude: Array[RID],
    maximum_distance: float = 250.0,
    last_accepted_sequence: int = -1,
    server_simulation_tick: int = -1
) -> Dictionary:
    # The future server owns the muzzle origin and collision world. Client
    # camera position, FOV, wall mode and displayed reticle are intentionally
    # absent from authority; only bounded aim intent crosses the network.
    var validation := validate_intent(
        payload,
        authoritative_muzzle_origin,
        last_accepted_sequence,
        server_simulation_tick
    )
    if not bool(validation.accepted):
        return validation

    var direction: Vector3 = validation.direction
    var query := PhysicsRayQueryParameters3D.create(
        authoritative_muzzle_origin,
        authoritative_muzzle_origin + direction * maximum_distance
    )
    query.exclude = exclude
    query.collide_with_areas = false
    var hit := world.direct_space_state.intersect_ray(query)
    return {
        "accepted": true,
        "accepted_sequence": int(payload.sequence),
        "accepted_tick": int(payload.simulation_tick),
        "hit": not hit.is_empty(),
        "position": hit.get(
            "position",
            authoritative_muzzle_origin + direction * maximum_distance
        ),
        "collider": hit.get("collider")
    }


static func validate_intent(
    payload: Dictionary,
    authoritative_muzzle_origin: Vector3,
    last_accepted_sequence: int = -1,
    server_simulation_tick: int = -1,
    maximum_tick_age: int = 18,
    maximum_future_ticks: int = 2,
    maximum_direction_error_deg: float = 12.0
) -> Dictionary:
    for field in [
        "sequence",
        "simulation_tick",
        "yaw",
        "pitch",
        "reported_muzzle_origin",
        "direction"
    ]:
        if not payload.has(field):
            return {"accepted": false, "reason": "MISSING_%s" % str(field).to_upper()}

    if typeof(payload.sequence) != TYPE_INT:
        return {"accepted": false, "reason": "INVALID_SEQUENCE"}
    if typeof(payload.simulation_tick) != TYPE_INT:
        return {"accepted": false, "reason": "INVALID_TICK"}
    var sequence: int = int(payload.sequence)
    var simulation_tick: int = int(payload.simulation_tick)
    if sequence <= last_accepted_sequence:
        return {"accepted": false, "reason": "STALE_SEQUENCE"}
    if server_simulation_tick >= 0:
        if simulation_tick < server_simulation_tick - maximum_tick_age:
            return {"accepted": false, "reason": "STALE_TICK"}
        if simulation_tick > server_simulation_tick + maximum_future_ticks:
            return {"accepted": false, "reason": "FUTURE_TICK"}

    var yaw_type: int = typeof(payload.yaw)
    var pitch_type: int = typeof(payload.pitch)
    if yaw_type not in [TYPE_FLOAT, TYPE_INT] or pitch_type not in [TYPE_FLOAT, TYPE_INT]:
        return {"accepted": false, "reason": "INVALID_ANGLES"}
    var yaw: float = float(payload.yaw)
    var pitch: float = float(payload.pitch)
    if is_nan(yaw) or is_inf(yaw) or is_nan(pitch) or is_inf(pitch):
        return {"accepted": false, "reason": "INVALID_ANGLES"}
    if yaw < -PI - 0.001 or yaw > PI + 0.001:
        return {"accepted": false, "reason": "YAW_OUT_OF_RANGE"}
    if pitch < deg_to_rad(-89.0) or pitch > deg_to_rad(89.0):
        return {"accepted": false, "reason": "PITCH_OUT_OF_RANGE"}

    if typeof(payload.reported_muzzle_origin) != TYPE_VECTOR3:
        return {"accepted": false, "reason": "INVALID_MUZZLE_ORIGIN"}
    if typeof(payload.direction) != TYPE_VECTOR3:
        return {"accepted": false, "reason": "INVALID_DIRECTION"}
    var reported_origin: Vector3 = payload.reported_muzzle_origin
    var direction: Vector3 = payload.direction
    if (
        not reported_origin.is_finite()
        or not direction.is_finite()
        or direction.length_squared() < 0.99
        or direction.length_squared() > 1.01
        or reported_origin.distance_to(authoritative_muzzle_origin) > 0.75
    ):
        return {"accepted": false, "reason": "INVALID_AIM_INTENT"}

    direction = direction.normalized()
    var yaw_basis := Basis(Vector3.UP, yaw)
    var yaw_forward := yaw_basis * Vector3.FORWARD
    var right := yaw_basis * Vector3.RIGHT
    var expected_direction := (Basis(right, pitch) * yaw_forward).normalized()
    if rad_to_deg(expected_direction.angle_to(direction)) > maximum_direction_error_deg:
        return {"accepted": false, "reason": "DIRECTION_ANGLE_MISMATCH"}
    return {"accepted": true, "direction": direction}
