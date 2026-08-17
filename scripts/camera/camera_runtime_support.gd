class_name SocomCameraRuntimeSupport
extends RefCounted

const VIRTUAL_WALL_OBSERVER_LAYER := 19

var rig
var target:
    get: return rig.target
    set(value): rig.target = value
var current_camera_position:
    get: return rig.current_camera_position
    set(value): rig.current_camera_position = value
var last_readable_post_solve_position:
    get: return rig.last_readable_post_solve_position
    set(value): rig.last_readable_post_solve_position = value
var previous_target_position:
    get: return rig.previous_target_position
    set(value): rig.previous_target_position = value
var target_position_initialized:
    get: return rig.target_position_initialized
    set(value): rig.target_position_initialized = value
var target_translation_blocked:
    get: return rig.target_translation_blocked
    set(value): rig.target_translation_blocked = value
var virtual_wall_occluder:
    get: return rig.virtual_wall_occluder
    set(value): rig.virtual_wall_occluder = value
var virtual_wall_original_layers:
    get: return rig.virtual_wall_original_layers
    set(value): rig.virtual_wall_original_layers = value
var camera:
    get: return rig.camera
    set(value): rig.camera = value

func configure(camera_rig) -> void:
    rig = camera_rig

func _cast_camera_volume(anchor: Vector3, destination: Vector3, exclude: Array[RID]) -> Dictionary:
    return rig._cast_camera_volume(anchor, destination, exclude)

func _follow_target_translation() -> void:
    target_translation_blocked = false
    var target_position: Vector3 = target.global_position
    if not target_position_initialized:
        previous_target_position = target_position
        target_position_initialized = true
        return
    var target_motion: Vector3 = target_position - previous_target_position
    previous_target_position = target_position
    if target_motion.length_squared() < 0.0000001:
        return
    # Spawn/test teleports get a fresh solve. Smoothing a camera across the map
    # is both slower and less readable than rebasing on the new player pose.
    if target_motion.length() > 1.50:
        rig.reset_camera_to_target()
        return
    if current_camera_position == Vector3.ZERO:
        return

    var exclude: Array[RID] = []
    if target is CollisionObject3D:
        exclude.append((target as CollisionObject3D).get_rid())
    var translated: Vector3 = current_camera_position + target_motion
    var translation_cast: Dictionary = _cast_camera_volume(
        current_camera_position,
        translated,
        exclude
    )
    var applied_motion: Vector3 = target_motion * clampf(
        float(translation_cast.safe_fraction),
        0.0,
        1.0
    )
    target_translation_blocked = float(translation_cast.safe_fraction) < 0.999
    current_camera_position += applied_motion
    if last_readable_post_solve_position != Vector3.ZERO:
        last_readable_post_solve_position += applied_motion

func _update_virtual_wall_occluder() -> void:
    # Solid world geometry always remains visible. Camera recovery is physical
    # now, so concealing the blocker would only reveal unfair information from
    # rooms or buildings behind it.
    _set_virtual_wall_occluder(null)

func _set_virtual_wall_occluder(blocker: Node3D) -> void:
    if blocker == virtual_wall_occluder:
        return
    for instance_id in virtual_wall_original_layers:
        var instance := instance_from_id(int(instance_id)) as GeometryInstance3D
        if instance:
            instance.layers = int(virtual_wall_original_layers[instance_id])
    virtual_wall_original_layers.clear()
    virtual_wall_occluder = blocker
    if blocker == null:
        return
    var geometry_nodes: Array[Node] = blocker.find_children(
        "*",
        "GeometryInstance3D",
        true,
        false
    )
    if blocker is GeometryInstance3D:
        geometry_nodes.append(blocker)
    for node in geometry_nodes:
        var geometry := node as GeometryInstance3D
        if geometry == null:
            continue
        virtual_wall_original_layers[geometry.get_instance_id()] = geometry.layers
        geometry.set_layer_mask_value(VIRTUAL_WALL_OBSERVER_LAYER, true)
        geometry.set_layer_mask_value(1, false)
