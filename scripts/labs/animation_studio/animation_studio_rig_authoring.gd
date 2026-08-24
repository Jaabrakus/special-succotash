extends "res://scripts/labs/animation_studio/animation_studio_pose_authoring.gd"

const EYE_ORIGIN_FORWARD_METERS := 0.13
const EYE_ORIGIN_HEIGHT_METERS := 0.09
const DIRECT_SCREEN_DRAG_TARGETS := [
    &"right_elbow_pole", &"left_elbow_pole",
    &"right_hand", &"left_hand", &"placement_origin",
]


func _select_animation_rig_target(target_id: StringName) -> void:
    _pause_for_pose_edit()
    animation_rig_selected_target = target_id
    selected_pose_bone = ""
    active_dragged_bone = ""
    active_pose_gizmo_handle = &""
    if animation_rig_overlay:
        animation_rig_overlay.set_selected_target(target_id)
    _refresh_animation_rig_selection_status()


func _toggle_animation_elbow_guides(enabled: bool) -> void:
    animation_elbow_guides_requested = enabled
    if animation_rig_overlay:
        animation_rig_overlay.set_elbow_guides_visible(
            enabled and _animation_preview_uses_ready_hand_solver()
        )
    if status_label:
        status_label.text = (
            "Pink elbow guides are visible. Drag one to change the arm's bend direction."
            if enabled
            else "Pink elbow guides are hidden. Hand and weapon controls are unchanged."
        )


func _begin_animation_rig_target_drag(target_id: StringName) -> void:
    animation_rig_drag_start_values = {
        "position": _animation_rig_target_position_value(target_id),
        "rotation": _animation_rig_target_rotation_value(target_id),
    }
    _sync_animation_preview_weapon_parent()


func _end_animation_rig_target_drag(_target_id: StringName) -> void:
    _sync_animation_preview_weapon_parent()


func _drag_animation_rig_target(
    target_id: StringName,
    axis: String,
    total_drag: Vector2,
    is_rotation: bool
) -> void:
    var start_position: Vector3 = animation_rig_drag_start_values.get("position", Vector3.ZERO)
    var start_rotation: Vector3 = animation_rig_drag_start_values.get("rotation", Vector3.ZERO)
    var scalar := total_drag.x - total_drag.y
    if is_rotation:
        var rotation := start_rotation
        rotation[_axis_index(axis)] += scalar * 0.18
        _set_animation_rig_target_rotation(target_id, rotation)
    else:
        var position := start_position
        var amount := (
            total_drag.x * 0.0015
            if axis == "x"
            else -total_drag.y * 0.0015
            if axis == "y"
            else scalar * 0.0011
        )
        position[_axis_index(axis)] += amount
        _set_animation_rig_target_position(target_id, position)
    _sync_animation_correction_controls()
    _apply_animation_correction_preview()
    _update_animation_rig_visual_overlay()


func _drag_animation_rig_target_screen(
    target_id: StringName,
    total_drag: Vector2
) -> void:
    if target_id not in DIRECT_SCREEN_DRAG_TARGETS:
        return
    var position: Vector3 = animation_rig_drag_start_values.get("position", Vector3.ZERO)
    position.x += total_drag.x * 0.0015
    position.y -= total_drag.y * 0.0015
    _set_animation_rig_target_position(target_id, position)
    _sync_animation_correction_controls()
    _apply_animation_correction_preview()
    _update_animation_rig_visual_overlay()


func _animation_rig_target_position_value(target_id: StringName) -> Vector3:
    match target_id:
        &"right_elbow_pole": return correction_right_elbow
        &"left_elbow_pole": return correction_left_elbow
        &"right_hand": return correction_right_hand
        &"left_hand": return correction_left_hand
        &"weapon_mount": return correction_weapon_position
        &"placement_origin": return correction_placement_position
        &"muzzle": return weapon_muzzle_marker.position if weapon_muzzle_marker else Vector3.ZERO
        &"barrel_base": return weapon_barrel_base_marker.position if weapon_barrel_base_marker else Vector3.ZERO
        &"ejection": return weapon_ejection_marker.position if weapon_ejection_marker else Vector3.ZERO
        &"optic": return weapon_optic_marker.position if weapon_optic_marker else Vector3.ZERO
    return Vector3.ZERO


func _animation_rig_target_rotation_value(target_id: StringName) -> Vector3:
    match target_id:
        &"right_hand": return correction_right_hand_rotation
        &"left_hand": return correction_left_hand_rotation
        &"weapon_mount": return correction_weapon_rotation
        &"placement_direction": return Vector3(0.0, 0.0, correction_placement_rotation.z)
    return Vector3.ZERO


func _set_animation_rig_target_position(target_id: StringName, value: Vector3) -> void:
    match target_id:
        &"right_elbow_pole": correction_right_elbow = _clamp_vector(value, 0.30)
        &"left_elbow_pole": correction_left_elbow = _clamp_vector(value, 0.30)
        &"right_hand": correction_right_hand = _clamp_vector(value, 1.50)
        &"left_hand": correction_left_hand = _clamp_vector(value, 1.20)
        &"weapon_mount": correction_weapon_position = _clamp_vector(value, 0.35)
        &"placement_origin": correction_placement_position = _clamp_vector(value, 1.0)
        &"muzzle":
            if weapon_muzzle_marker: weapon_muzzle_marker.position = _clamp_vector(value, 2.0)
        &"barrel_base":
            if weapon_barrel_base_marker: weapon_barrel_base_marker.position = _clamp_vector(value, 2.0)
        &"ejection":
            if weapon_ejection_marker: weapon_ejection_marker.position = _clamp_vector(value, 2.0)
        &"optic":
            if weapon_optic_marker: weapon_optic_marker.position = _clamp_vector(value, 2.0)


func _set_animation_rig_target_rotation(target_id: StringName, value: Vector3) -> void:
    var safe := Vector3(
        clampf(value.x, -180.0, 180.0),
        clampf(value.y, -180.0, 180.0),
        clampf(value.z, -180.0, 180.0)
    )
    match target_id:
        &"right_hand": correction_right_hand_rotation = safe
        &"left_hand": correction_left_hand_rotation = safe
        &"weapon_mount": correction_weapon_rotation = safe
        &"placement_direction": correction_placement_rotation.z = safe.z


func _refresh_animation_rig_selection_status() -> void:
    if status_label == null:
        return
    var labels := {
        &"right_elbow_pole": "Right Elbow IK Pole",
        &"left_elbow_pole": "Left Elbow IK Pole",
        &"right_hand": "Trigger-Hand Grip",
        &"left_hand": "Support-Hand Grip",
        &"weapon_mount": "Animation Weapon Mount",
        &"muzzle": "Muzzle Socket",
        &"barrel_base": "Barrel Base Socket",
        &"ejection": "Ejection Socket",
        &"optic": "Optic Rail Socket",
        &"placement_origin": "Blue Placement Origin",
        &"placement_direction": "Blue Placement Direction",
    }
    var instruction := (
        "Direction is locked to the center reticle. Move the dark-blue origin to place the gun."
        if animation_rig_selected_target == &"placement_direction"
        else "Drag this dot to move it, or use the corner XYZ/rotation control. Then save the correction key."
    )
    status_label.text = "Selected %s. %s" % [labels.get(
        animation_rig_selected_target,
        String(animation_rig_selected_target)
    ), instruction]


func _load_animation_placement_reference(clip_key: String) -> void:
    animation_rig_placement_clip_key = clip_key
    correction_placement_position = Vector3.ZERO
    correction_placement_rotation = Vector3.ZERO
    var raw_line: Variant = gunsmith_weapon_config.get("gun_placement_line", {})
    if not raw_line is Dictionary:
        return
    var by_stance: Variant = (raw_line as Dictionary).get("by_stance", {})
    if not by_stance is Dictionary:
        return
    var posture := _animation_correction_posture(clip_key)
    var raw_stance: Variant = (by_stance as Dictionary).get(posture, {})
    if not raw_stance is Dictionary:
        return
    var stance := raw_stance as Dictionary
    correction_placement_position = animation_correction_overlay.vector_from(
        stance.get("position_offset_meters", {})
    )
    correction_placement_rotation = Vector3(
        0.0,
        0.0,
        float(stance.get("roll_degrees", 0.0))
    )


func _store_animation_placement_reference(clip_key: String) -> void:
    var line: Dictionary = (
        gunsmith_weapon_config.get("gun_placement_line", {}).duplicate(true)
        if gunsmith_weapon_config.get("gun_placement_line", {}) is Dictionary
        else {}
    )
    var by_stance: Dictionary = (
        line.get("by_stance", {}).duplicate(true)
        if line.get("by_stance", {}) is Dictionary
        else {}
    )
    by_stance[_animation_correction_posture(clip_key)] = {
        "position_offset_meters": animation_correction_overlay.vector_map(correction_placement_position),
        "pitch_degrees": 0.0,
        "yaw_degrees": 0.0,
        "roll_degrees": correction_placement_rotation.z,
    }
    line["space"] = "operator_local_weapon_placement"
    line["direction_mode"] = "reticle_locked"
    line["by_stance"] = by_stance
    gunsmith_weapon_config["gun_placement_line"] = line


func _store_animation_socket_reference() -> void:
    var sockets: Dictionary = (
        gunsmith_weapon_config.get("weapon_sockets", {}).duplicate(true)
        if gunsmith_weapon_config.get("weapon_sockets", {}) is Dictionary
        else {}
    )
    if weapon_muzzle_marker:
        sockets["muzzle_socket"] = animation_correction_overlay.vector_map(weapon_muzzle_marker.position)
    if weapon_barrel_base_marker:
        sockets["barrel_base_socket"] = animation_correction_overlay.vector_map(weapon_barrel_base_marker.position)
    if weapon_ejection_marker:
        sockets["ejection_port"] = animation_correction_overlay.vector_map(weapon_ejection_marker.position)
    if weapon_optic_marker:
        sockets["optic_rail"] = animation_correction_overlay.vector_map(weapon_optic_marker.position)
    gunsmith_weapon_config["weapon_sockets"] = sockets


func _animation_placement_origin_world() -> Vector3:
    if skeleton == null:
        return Vector3.ZERO
    var basis := skeleton.global_basis.orthonormalized()
    var posture := _animation_correction_posture(
        _active_animation_correction_clip_key()
    )
    var head_origin := _animation_rig_bone_world([
        "mixamorig_Head", "mixamorig:Head", "head", "Bip01 Head"
    ])
    var live_head_reference := (
        head_origin
        + basis.y * EYE_ORIGIN_HEIGHT_METERS
        + basis.z * EYE_ORIGIN_FORWARD_METERS
    )
    if not animation_placement_anchor_local_by_posture.has(posture):
        # Store the user's stance offset, not an absolute world point. The
        # reference must rise and lower with the animated head in standing,
        # crouched, and prone poses, while its direction remains reticle-locked.
        animation_placement_anchor_local_by_posture[posture] = Vector3.ZERO
    var stance_offset: Vector3 = animation_placement_anchor_local_by_posture[posture]
    var neutral_origin := (
        live_head_reference
        + basis.x * stance_offset.x
        + basis.y * stance_offset.y
        + basis.z * stance_offset.z
    )
    return (
        neutral_origin
        + basis.x * correction_placement_position.x
        + basis.y * correction_placement_position.y
        + basis.z * correction_placement_position.z
    )


func _animation_placement_direction_world() -> Vector3:
    if skeleton == null or camera == null:
        return Vector3.FORWARD
    return GUN_PLACEMENT_PROFILE.reticle_locked_direction(
        camera,
        _animation_placement_origin_world(),
        _animation_workbench_center_screen()
    )


func _animation_rig_bone_world(candidates: Array[String]) -> Vector3:
    for candidate in candidates:
        var index := skeleton.find_bone(candidate)
        if index >= 0:
            return (skeleton.global_transform * skeleton.get_bone_global_pose(index)).origin
    return skeleton.global_position


func _axis_index(axis: String) -> int:
    return 0 if axis == "x" else 1 if axis == "y" else 2


func _clamp_vector(value: Vector3, limit: float) -> Vector3:
    return Vector3(
        clampf(value.x, -limit, limit),
        clampf(value.y, -limit, limit),
        clampf(value.z, -limit, limit)
    )
