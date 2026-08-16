class_name SocomShotAuthority
extends RefCounted


static func validate_and_trace(
    world: World3D,
    payload: Dictionary,
    authoritative_muzzle_origin: Vector3,
    exclude: Array[RID],
    maximum_distance: float = 250.0
) -> Dictionary:
    # The future server owns the muzzle origin and collision world. Client
    # camera position, FOV, wall mode and displayed reticle are intentionally
    # absent from authority; only bounded aim intent crosses the network.
    var reported_origin: Vector3 = payload.get(
        "reported_muzzle_origin",
        authoritative_muzzle_origin
    )
    var direction: Vector3 = payload.get("direction", Vector3.ZERO)
    if (
        not direction.is_finite()
        or direction.length_squared() < 0.99
        or direction.length_squared() > 1.01
        or reported_origin.distance_to(authoritative_muzzle_origin) > 0.75
    ):
        return {"accepted": false, "reason": "INVALID_AIM_INTENT"}

    direction = direction.normalized()
    var query := PhysicsRayQueryParameters3D.create(
        authoritative_muzzle_origin,
        authoritative_muzzle_origin + direction * maximum_distance
    )
    query.exclude = exclude
    query.collide_with_areas = false
    var hit := world.direct_space_state.intersect_ray(query)
    return {
        "accepted": true,
        "hit": not hit.is_empty(),
        "position": hit.get(
            "position",
            authoritative_muzzle_origin + direction * maximum_distance
        ),
        "collider": hit.get("collider")
    }
