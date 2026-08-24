class_name SocomShotAuthority
extends RefCounted

const AnatomicalHitResolver := preload("res://scripts/combat/socom_anatomical_hit_resolver.gd")
const DEFAULT_MUZZLE_FORWARD_CLEARANCE_M := 0.18


static func validate_muzzle_clearance(
    space_state: PhysicsDirectSpaceState3D,
    authoritative_report_anchor: Vector3,
    authoritative_muzzle_origin: Vector3,
    authoritative_shot_direction: Vector3,
    exclude: Array[RID],
    forward_clearance_m: float = DEFAULT_MUZZLE_FORWARD_CLEARANCE_M
) -> Dictionary:
    # This segment is built entirely from server-owned transforms and world
    # collision. Client camera placement and client obstruction claims are not
    # inputs, so a muzzle animated through nearby cover cannot shoot past it.
    if space_state == null:
        return {"accepted": false, "reason": "MUZZLE_CLEARANCE_WORLD_UNAVAILABLE"}
    if (
        not authoritative_report_anchor.is_finite()
        or not authoritative_muzzle_origin.is_finite()
        or not authoritative_shot_direction.is_finite()
        or authoritative_shot_direction.length_squared() < 0.99
    ):
        return {"accepted": false, "reason": "MUZZLE_CLEARANCE_INVALID"}
    var direction := authoritative_shot_direction.normalized()
    var trace_end := (
        authoritative_muzzle_origin
        + direction * clampf(forward_clearance_m, 0.0, 0.5)
    )
    if authoritative_report_anchor.distance_squared_to(trace_end) < 0.000001:
        return {"accepted": true}
    var query := PhysicsRayQueryParameters3D.create(
        authoritative_report_anchor,
        trace_end
    )
    query.exclude = exclude
    query.collide_with_areas = false
    query.collide_with_bodies = true
    query.hit_from_inside = true
    var obstruction := space_state.intersect_ray(query)
    if obstruction.is_empty():
        return {"accepted": true}
    return {
        "accepted": false,
        "reason": "MUZZLE_OBSTRUCTED",
        "position": Vector3(obstruction.get("position", authoritative_muzzle_origin)),
        "normal": Vector3(obstruction.get("normal", Vector3.ZERO)),
        "collider": obstruction.get("collider"),
        "collider_id": int(obstruction.get("collider_id", 0)),
    }


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
        Vector3(payload.get("reported_muzzle_origin", authoritative_muzzle_origin)),
        last_accepted_sequence,
        server_simulation_tick
    )
    if not bool(validation.accepted):
        return validation

    var direction := resolve_trace_direction(
        validation,
        Vector3(payload.get("reported_muzzle_origin", authoritative_muzzle_origin)),
        authoritative_muzzle_origin
    )
    var hit := AnatomicalHitResolver.trace(
        world.direct_space_state,
        authoritative_muzzle_origin,
        authoritative_muzzle_origin + direction * maximum_distance,
        exclude
    )
    var collider: Object = hit.get("collider")
    var hit_region: StringName = &""
    var damage_receiver: Node = null
    if collider != null and collider.has_method("get_hit_region"):
        hit_region = StringName(collider.call("get_hit_region"))
    elif hit.has("hit_region"):
        hit_region = StringName(hit.hit_region)
    if collider != null and collider.has_method("get_damage_receiver"):
        damage_receiver = collider.call("get_damage_receiver") as Node
    return {
        "accepted": true,
        "accepted_sequence": int(payload.sequence),
        "accepted_tick": int(payload.simulation_tick),
        "hit": not hit.is_empty(),
        "position": hit.get(
            "position",
            authoritative_muzzle_origin + direction * maximum_distance
        ),
        "collider": collider,
        "damage_receiver": damage_receiver,
        "hit_region": hit_region,
        "anatomical_override": bool(hit.get("anatomical_override", false)),
        "occluding_region": StringName(hit.get("occluding_region", &"")),
        "overlap_depth_m": float(hit.get("overlap_depth_m", 0.0))
    }


static func validate_intent(
    payload: Dictionary,
    authoritative_muzzle_origin: Vector3,
    last_accepted_sequence: int = -1,
    server_simulation_tick: int = -1,
    maximum_tick_age: int = 18,
    maximum_future_ticks: int = 2,
    maximum_direction_error_deg: float = 12.0,
    maximum_report_anchor_error_m: float = 1.5
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
    if not reported_origin.is_finite():
        return {"accepted": false, "reason": "INVALID_MUZZLE_ORIGIN"}
    if reported_origin.distance_to(authoritative_muzzle_origin) > maximum_report_anchor_error_m:
        return {"accepted": false, "reason": "REPORT_ANCHOR_OUT_OF_RANGE"}
    if (
        not direction.is_finite()
        or direction.length_squared() < 0.99
        or direction.length_squared() > 1.01
    ):
        return {"accepted": false, "reason": "INVALID_DIRECTION"}
    # Do not compare a client presentation anchor to the animated server muzzle.
    # Prediction, reconciliation and animation phase can move those visuals
    # independently. The server never traces from this reported point; it owns
    # authoritative_muzzle_origin and uses it for all collision and damage.

    direction = direction.normalized()
    var yaw_basis := Basis(Vector3.UP, yaw)
    var yaw_forward := yaw_basis * Vector3.FORWARD
    var right := yaw_basis * Vector3.RIGHT
    var expected_direction := (Basis(right, pitch) * yaw_forward).normalized()
    if rad_to_deg(expected_direction.angle_to(direction)) > maximum_direction_error_deg:
        return {"accepted": false, "reason": "DIRECTION_ANGLE_MISMATCH"}
    var result := {"accepted": true, "direction": direction}
    if payload.has("convergence_distance"):
        var convergence_type := typeof(payload.convergence_distance)
        if convergence_type not in [TYPE_FLOAT, TYPE_INT]:
            return {"accepted": false, "reason": "INVALID_CONVERGENCE_DISTANCE"}
        var convergence_distance := float(payload.convergence_distance)
        if (
            is_nan(convergence_distance)
            or is_inf(convergence_distance)
            or convergence_distance < 0.25
            or convergence_distance > 250.0
        ):
            return {"accepted": false, "reason": "INVALID_CONVERGENCE_DISTANCE"}
        result["convergence_distance"] = convergence_distance
    return result


static func resolve_trace_direction(
    validation: Dictionary,
    authoritative_report_anchor: Vector3,
    authoritative_muzzle_origin: Vector3
) -> Vector3:
    var intent_direction := Vector3(validation.get("direction", Vector3.FORWARD)).normalized()
    if not validation.has("convergence_distance"):
        return intent_direction
    var target := (
        authoritative_report_anchor
        + intent_direction * float(validation.convergence_distance)
    )
    var converged := authoritative_muzzle_origin.direction_to(target)
    return converged if converged.length_squared() >= 0.99 else intent_direction
