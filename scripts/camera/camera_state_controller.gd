class_name SocomCameraStateController
extends RefCounted

enum CameraState {
    PREFERRED,
    COMPRESSED,
    POST_SOLVED,
    PERCHED,
    RELEASE
}

var rig

func configure(camera_rig) -> void:
    rig = camera_rig

func apply_collision_result(result: Dictionary) -> void:
    rig.collision_camera_position = result.position
    rig.collision_active = result.collided
    rig.collision_name = result.collider_name
    rig.collision_blocker_node = _live_node_3d(result.get("collider_node"))
    rig.wall_escape_active = result.escaped
    rig.wall_escape_angle_deg = result.escape_angle_deg
    rig.local_cutout_active = result.local_cutout
    rig.local_cutout_center = result.cutout_center
    rig.local_cutout_node = _live_node_3d(result.get("cutout_node"))
    rig.collision_crane_active = bool(result.get("crane_active", false))
    rig.surface_slide_active = bool(result.get("surface_slide_active", false))
    rig.surface_slide_normal = result.get("surface_slide_normal", Vector3.ZERO)
    rig.near_body_crop_active = bool(result.get("near_body_crop_active", false))
    if rig.collision_crane_active:
        rig.collision_crane_look_ahead = float(result.get(
            "crane_look_ahead",
            rig.profile.close_wall_crane_default_look_ahead
        ))

func _live_node_3d(value: Variant) -> Node3D:
    # Release guards retain result dictionaries after a wall may be freed.
    # Validate the Variant before any cast or subtype check dereferences it.
    if typeof(value) != TYPE_OBJECT or not is_instance_valid(value):
        return null
    return value as Node3D if value is Node3D else null

func update_collision_crane_view(delta: float) -> void:
    var view_target: float = 1.0 if rig.collision_crane_active else 0.0
    var response: float = (
        rig.profile.close_wall_crane_enter_response
        if view_target > 0.5
        else rig.profile.close_wall_crane_exit_response
    )
    rig.collision_crane_view_amount = lerpf(
        rig.collision_crane_view_amount,
        view_target,
        1.0 - exp(-response * delta)
    )

func update_wall_context(delta: float) -> void:
    var context_target: float = 1.0 if rig.collision_active else 0.0
    var context_response: float = (
        rig.profile.wall_context_enter_response
        if rig.collision_active
        else rig.profile.wall_context_exit_response
    )
    rig.wall_context_amount = lerpf(
        rig.wall_context_amount,
        context_target,
        1.0 - exp(-context_response * delta)
    )

func update_state(delta: float) -> void:
    rig.camera_state_age += delta
    var requested := CameraState.PREFERRED
    if rig.collision_crane_active or rig.collision_crane_view_amount >= 0.55:
        requested = CameraState.PERCHED
    elif rig.collision_active and rig.post_collision_reframe:
        requested = CameraState.POST_SOLVED
    elif rig.collision_active:
        requested = CameraState.COMPRESSED
    elif (
        rig.camera_state != CameraState.PREFERRED
        and (
            rig.wall_context_amount > 0.04
            or rig.current_camera_position.distance_to(rig.collision_camera_position)
                > rig.profile.wall_branch_transition_distance
        )
    ):
        requested = CameraState.RELEASE

    if requested == rig.camera_state:
        return

    var safety_entry: bool = (
        requested == CameraState.COMPRESSED
        or requested == CameraState.POST_SOLVED
        or requested == CameraState.PERCHED
    )
    if not safety_entry and rig.camera_state_age < 0.12:
        return
    rig.camera_state = requested
    rig.camera_state_age = 0.0
    rig.camera_state_transition_count += 1

func state_name(state: int) -> String:
    match state:
        CameraState.PREFERRED:
            return "PREFERRED"
        CameraState.COMPRESSED:
            return "COMPRESSED"
        CameraState.POST_SOLVED:
            return "POST-SOLVED"
        CameraState.PERCHED:
            return "PERCHED"
        CameraState.RELEASE:
            return "RELEASE"
    return "UNKNOWN"
