extends "res://scripts/labs/animation_studio/animation_studio_pose_strip.gd"

func _toggle_animation_correction_overlay(enabled: bool) -> void:
    animation_correction_enabled = enabled
    if animation_correction_panel:
        animation_correction_panel.visible = enabled
    animation_correction_last_frame = -1
    if not enabled:
        _restore_raw_animation_frame()
        _refresh_animation_correction_label()
        return
    _pause_for_pose_edit()
    _capture_animation_correction_bases()
    _load_animation_correction_at_current_frame(true)
    if status_label:
        status_label.text = (
            "Correction Overlay is ON. Joint, hand, and weapon edits remain additive to the imported clip."
        )

func _active_animation_correction_entry() -> Dictionary:
    if filtered_entries.is_empty() or clip_index < 0 or clip_index >= filtered_entries.size():
        return {}
    return filtered_entries[clip_index]

func _active_animation_correction_clip_key() -> String:
    return animation_correction_overlay.resolve_clip_key(
        _active_animation_correction_entry(),
        state_slots,
        selected_state_slot
    )

func _capture_animation_correction_bases() -> void:
    if weapon_calibrated_pivot:
        correction_weapon_base_transform = weapon_calibrated_pivot.transform
    if right_hand_marker:
        correction_right_hand_base = right_hand_marker.position
        correction_right_hand_rotation_base = right_hand_marker.rotation_degrees
    if left_hand_marker:
        correction_left_hand_base = left_hand_marker.position
        correction_left_hand_rotation_base = left_hand_marker.rotation_degrees

func _restore_raw_animation_frame() -> void:
    bone_rot_offsets.clear()
    bone_pos_offsets.clear()
    bone_edit_base_poses.clear()
    if animation_player and not animation_player.current_animation.is_empty():
        var current_time := animation_player.current_animation_position
        animation_player.seek(current_time, true)
    if weapon_calibrated_pivot:
        weapon_calibrated_pivot.transform = correction_weapon_base_transform
    if right_hand_marker:
        right_hand_marker.position = correction_right_hand_base
        right_hand_marker.rotation_degrees = correction_right_hand_rotation_base
    if left_hand_marker:
        left_hand_marker.position = correction_left_hand_base
        left_hand_marker.rotation_degrees = correction_left_hand_rotation_base
    _sync_pose_sliders_from_selection()

func _load_animation_correction_at_current_frame(force: bool = false) -> void:
    if not animation_correction_enabled or skeleton == null:
        return
    var frame := _current_pose_frame()
    if not force and frame == animation_correction_last_frame:
        return
    animation_correction_last_frame = frame
    var clip_key := _active_animation_correction_clip_key()
    if force or animation_rig_placement_clip_key != clip_key:
        _load_animation_placement_reference(clip_key)
    var pose_keys: Dictionary = gunsmith_weapon_config.get("animation_frame_pose_keys", {})
    var pose: Dictionary = animation_correction_overlay.sample(pose_keys, clip_key, frame)
    bone_rot_offsets.clear()
    bone_pos_offsets.clear()
    bone_edit_base_poses.clear()
    var rotations: Dictionary = pose.get("joint_rotations", {})
    for bone_index in range(skeleton.get_bone_count()):
        var bone_name := String(skeleton.get_bone_name(bone_index))
        var joint_name := animation_correction_overlay.joint_name_for_bone(bone_name)
        if not joint_name.is_empty() and rotations.has(joint_name):
            bone_rot_offsets[bone_name] = animation_correction_overlay.vector_from(
                rotations[joint_name]
            )
    correction_right_hand = animation_correction_overlay.vector_from(
        pose.get("right_hand_target", {}), correction_right_hand_base
    )
    correction_left_hand = animation_correction_overlay.vector_from(
        pose.get("left_hand_target", {}), correction_left_hand_base
    )
    correction_right_hand_rotation = animation_correction_overlay.vector_from(
        pose.get("right_hand_rotation_correction_deg", {})
    )
    correction_left_hand_rotation = animation_correction_overlay.vector_from(
        pose.get("left_hand_rotation_correction_deg", {})
    )
    correction_right_elbow = animation_correction_overlay.vector_from(
        pose.get("right_elbow_pole", {}),
        _default_animation_elbow_pole(&"right", clip_key)
    )
    correction_left_elbow = animation_correction_overlay.vector_from(
        pose.get("left_elbow_pole", {}),
        _default_animation_elbow_pole(&"left", clip_key)
    )
    correction_weapon_position = animation_correction_overlay.vector_from(
        pose.get("weapon_hand_position_correction", {})
    )
    correction_weapon_rotation = animation_correction_overlay.vector_from(
        pose.get("weapon_hand_rotation_correction_deg", {})
    )
    _sync_animation_correction_controls()
    _sync_pose_sliders_from_selection()
    _apply_animation_correction_preview()
    _refresh_animation_correction_label()

func _update_animation_correction_overlay() -> void:
    if active_editor_page != "Pose" or not animation_correction_enabled:
        return
    _load_animation_correction_at_current_frame()
    _apply_animation_correction_preview()

func _update_animation_rig_visual_overlay() -> void:
    if animation_rig_overlay == null:
        return
    var is_pose_editor := active_editor_page == "Pose"
    var is_state_reference := active_editor_page == "States"
    var is_casting_reference := (
        active_editor_page == "Casting" and animation_casting_show_grip_guides
    )
    if not is_pose_editor and not is_state_reference and not is_casting_reference:
        animation_rig_overlay.visible = false
        return
    var placement_origin := _animation_placement_origin_world()
    var placement_direction := _animation_placement_direction_world()
    if (
        is_state_reference
        and (
            state_event_effect_active_seconds > 0.0
            or state_event_effect_release_seconds > 0.0
        )
    ):
        # The blue line is the fixed authoring target. The rifle and hands move
        # toward it; the target must never be replaced by the solver output.
        # Otherwise the dot follows the weapon that is meant to chase it.
        var event_direction := state_event_effect_forward_direction.normalized()
        if event_direction.length_squared() > 0.5:
            placement_direction = event_direction
    var reference_mode := is_state_reference or is_casting_reference
    var ready_hands := (
        true if reference_mode else _animation_preview_uses_ready_hand_solver()
    )
    animation_rig_overlay.set_preview_reference_mode(reference_mode)
    animation_rig_overlay.set_hand_guides_active(ready_hands)
    animation_rig_overlay.set_elbow_guides_visible(
        animation_elbow_guides_requested and ready_hands and is_pose_editor
    )
    animation_rig_overlay.update_overlay(
        skeleton,
        weapon_calibrated_pivot,
        right_hand_marker,
        left_hand_marker,
        weapon_barrel_base_marker,
        weapon_muzzle_marker,
        weapon_ejection_marker,
        weapon_optic_marker,
        correction_right_elbow,
        correction_left_elbow,
        placement_origin,
        placement_direction,
        selected_pose_bone
    )

func _apply_animation_correction_preview() -> void:
    if not animation_correction_enabled:
        return
    if right_hand_marker:
        right_hand_marker.position = correction_right_hand
        right_hand_marker.rotation_degrees = (
            correction_right_hand_rotation_base + correction_right_hand_rotation
        )
    if left_hand_marker:
        left_hand_marker.position = correction_left_hand
        left_hand_marker.rotation_degrees = (
            correction_left_hand_rotation_base + correction_left_hand_rotation
        )
    if weapon_calibrated_pivot:
        var rotation_radians := Vector3(
            deg_to_rad(correction_weapon_rotation.x),
            deg_to_rad(correction_weapon_rotation.y),
            deg_to_rad(correction_weapon_rotation.z)
        )
        weapon_calibrated_pivot.transform = correction_weapon_base_transform * Transform3D(
            Basis.from_euler(rotation_radians),
            correction_weapon_position
        )

func _set_animation_correction_value(key: String, value: float) -> void:
    if animation_correction_syncing:
        return
    if not animation_correction_enabled:
        animation_correction_enabled = true
        if animation_correction_toggle:
            animation_correction_toggle.set_pressed_no_signal(true)
        _capture_animation_correction_bases()
    match key:
        "right_hand_x": correction_right_hand.x = value
        "right_hand_y": correction_right_hand.y = value
        "right_hand_z": correction_right_hand.z = value
        "left_hand_x": correction_left_hand.x = value
        "left_hand_y": correction_left_hand.y = value
        "left_hand_z": correction_left_hand.z = value
        "right_hand_rot_x": correction_right_hand_rotation.x = value
        "right_hand_rot_y": correction_right_hand_rotation.y = value
        "right_hand_rot_z": correction_right_hand_rotation.z = value
        "left_hand_rot_x": correction_left_hand_rotation.x = value
        "left_hand_rot_y": correction_left_hand_rotation.y = value
        "left_hand_rot_z": correction_left_hand_rotation.z = value
        "right_elbow_x": correction_right_elbow.x = value
        "right_elbow_y": correction_right_elbow.y = value
        "right_elbow_z": correction_right_elbow.z = value
        "left_elbow_x": correction_left_elbow.x = value
        "left_elbow_y": correction_left_elbow.y = value
        "left_elbow_z": correction_left_elbow.z = value
        "weapon_pos_x": correction_weapon_position.x = value
        "weapon_pos_y": correction_weapon_position.y = value
        "weapon_pos_z": correction_weapon_position.z = value
        "weapon_rot_x": correction_weapon_rotation.x = value
        "weapon_rot_y": correction_weapon_rotation.y = value
        "weapon_rot_z": correction_weapon_rotation.z = value
    _apply_animation_correction_preview()

func _sync_animation_correction_controls() -> void:
    if animation_correction_controls.is_empty():
        return
    animation_correction_syncing = true
    var values := {
        "right_hand_x": correction_right_hand.x,
        "right_hand_y": correction_right_hand.y,
        "right_hand_z": correction_right_hand.z,
        "left_hand_x": correction_left_hand.x,
        "left_hand_y": correction_left_hand.y,
        "left_hand_z": correction_left_hand.z,
        "right_hand_rot_x": correction_right_hand_rotation.x,
        "right_hand_rot_y": correction_right_hand_rotation.y,
        "right_hand_rot_z": correction_right_hand_rotation.z,
        "left_hand_rot_x": correction_left_hand_rotation.x,
        "left_hand_rot_y": correction_left_hand_rotation.y,
        "left_hand_rot_z": correction_left_hand_rotation.z,
        "right_elbow_x": correction_right_elbow.x,
        "right_elbow_y": correction_right_elbow.y,
        "right_elbow_z": correction_right_elbow.z,
        "left_elbow_x": correction_left_elbow.x,
        "left_elbow_y": correction_left_elbow.y,
        "left_elbow_z": correction_left_elbow.z,
        "weapon_pos_x": correction_weapon_position.x,
        "weapon_pos_y": correction_weapon_position.y,
        "weapon_pos_z": correction_weapon_position.z,
        "weapon_rot_x": correction_weapon_rotation.x,
        "weapon_rot_y": correction_weapon_rotation.y,
        "weapon_rot_z": correction_weapon_rotation.z,
    }
    for key in values.keys():
        if not animation_correction_controls.has(key):
            continue
        var control: Dictionary = animation_correction_controls[key]
        var slider := control.get("slider") as HSlider
        var value_label := control.get("label") as Label
        if slider:
            slider.set_value_no_signal(float(values[key]))
        if value_label:
            value_label.text = (
                "%.1f°" % float(values[key])
                if "_rot_" in String(key)
                else "%.3f" % float(values[key])
            )
    animation_correction_syncing = false

func _animation_correction_pose() -> Dictionary:
    var clip_key := _active_animation_correction_clip_key()
    var pose_keys: Dictionary = gunsmith_weapon_config.get("animation_frame_pose_keys", {})
    var pose := animation_correction_overlay.sample(
        pose_keys, clip_key, _current_pose_frame()
    )
    var rotations: Dictionary = pose.get("joint_rotations", {}).duplicate(true)
    for raw_bone_name in bone_rot_offsets.keys():
        var joint_name := animation_correction_overlay.joint_name_for_bone(
            String(raw_bone_name)
        )
        if not joint_name.is_empty():
            rotations[joint_name] = animation_correction_overlay.vector_map(
                bone_rot_offsets[raw_bone_name]
            )
    pose["joint_rotations"] = rotations
    pose["right_hand_target"] = animation_correction_overlay.vector_map(correction_right_hand)
    pose["left_hand_target"] = animation_correction_overlay.vector_map(correction_left_hand)
    pose["right_hand_rotation_correction_deg"] = animation_correction_overlay.vector_map(
        correction_right_hand_rotation
    )
    pose["left_hand_rotation_correction_deg"] = animation_correction_overlay.vector_map(
        correction_left_hand_rotation
    )
    pose["right_elbow_pole"] = animation_correction_overlay.vector_map(
        correction_right_elbow
    )
    pose["left_elbow_pole"] = animation_correction_overlay.vector_map(
        correction_left_elbow
    )
    pose["weapon_hand_position_correction"] = animation_correction_overlay.vector_map(
        correction_weapon_position
    )
    pose["weapon_hand_rotation_correction_deg"] = animation_correction_overlay.vector_map(
        correction_weapon_rotation
    )
    if not pose.has("posture"):
        pose["posture"] = _animation_correction_posture(clip_key)
    return pose

func _animation_correction_posture(clip_key: String) -> String:
    var lower := clip_key.to_lower()
    # Animation names are not consistent about posture.  In particular, the
    # imported prone locomotion set is named "... Crawl Position" and the
    # crouch set also uses "kneel/kneeling".  Keep these aliases here so the
    # blue placement anchor, elbow poles, and saved corrections all resolve to
    # the same stance instead of silently borrowing STANDING.
    if "prone" in lower or "crawl" in lower:
        return "PRONE"
    if "crouch" in lower or "kneel" in lower:
        return "CROUCHED"
    return "STANDING"

func _default_animation_elbow_pole(side: StringName, clip_key: String) -> Vector3:
    var raw_poles: Variant = gunsmith_weapon_config.get("elbow_poles", {})
    if not raw_poles is Dictionary:
        return Vector3.ZERO
    var poles := raw_poles as Dictionary
    var by_stance: Variant = poles.get("by_stance", {})
    var posture := _animation_correction_posture(clip_key)
    if by_stance is Dictionary:
        var stance_value: Variant = (by_stance as Dictionary).get(posture, {})
        if stance_value is Dictionary:
            var side_value: Variant = (stance_value as Dictionary).get(String(side), {})
            if side_value is Dictionary:
                return animation_correction_overlay.vector_from(side_value)
    return animation_correction_overlay.vector_from(
        poles.get(String(side), {})
    )

func _save_animation_correction_key() -> void:
    if loaded_gunsmith_config_path.is_empty() or gunsmith_weapon_config.is_empty():
        status_label.text = "Equip a saved weapon before writing animation corrections."
        return
    if not animation_correction_enabled:
        _toggle_animation_correction_overlay(true)
    var clip_key := _active_animation_correction_clip_key()
    if clip_key.is_empty():
        status_label.text = "Choose a mapped animation before saving a correction."
        return
    var pose_keys: Dictionary = gunsmith_weapon_config.get("animation_frame_pose_keys", {})
    gunsmith_weapon_config["animation_frame_pose_keys"] = animation_correction_overlay.store_key(
        pose_keys,
        clip_key,
        _current_pose_frame(),
        _animation_correction_pose()
    )
    _store_animation_placement_reference(clip_key)
    _store_animation_socket_reference()
    if not _write_animation_correction_profile():
        status_label.text = "The equipped weapon profile could not be written."
        return
    animation_correction_last_frame = -1
    _load_animation_correction_at_current_frame(true)
    status_label.text = (
        "Saved %s correction at frame %d. It blends with the imported animation."
        % [clip_key, _current_pose_frame()]
    )

func _delete_animation_correction_key() -> void:
    if loaded_gunsmith_config_path.is_empty() or gunsmith_weapon_config.is_empty():
        return
    var clip_key := _active_animation_correction_clip_key()
    var pose_keys: Dictionary = gunsmith_weapon_config.get("animation_frame_pose_keys", {})
    gunsmith_weapon_config["animation_frame_pose_keys"] = animation_correction_overlay.delete_key(
        pose_keys, clip_key, _current_pose_frame()
    )
    if not _write_animation_correction_profile():
        status_label.text = "The equipped weapon profile could not be written."
        return
    animation_correction_last_frame = -1
    _load_animation_correction_at_current_frame(true)
    status_label.text = "Deleted the %s correction key at frame %d." % [
        clip_key, _current_pose_frame()
    ]

func _write_animation_correction_profile() -> bool:
    var document := gunsmith_weapon_config.duplicate(true)
    document.erase("_rig_config_path")
    var file := FileAccess.open(loaded_gunsmith_config_path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(document, "  "))
    file.close()
    gunsmith_weapon_config = document
    gunsmith_weapon_config["_rig_config_path"] = loaded_gunsmith_config_path
    return true

func _refresh_animation_correction_label() -> void:
    if animation_correction_label == null:
        return
    if not animation_correction_enabled:
        animation_correction_label.text = "CORRECTION OVERLAY: OFF — raw imported animation"
        return
    var clip_key := _active_animation_correction_clip_key()
    var pose_keys: Dictionary = gunsmith_weapon_config.get("animation_frame_pose_keys", {})
    var clip_frames: Dictionary = (
        pose_keys.get(clip_key, {}) as Dictionary
        if pose_keys.get(clip_key, {}) is Dictionary
        else {}
    )
    var frames := clip_frames.keys()
    frames.sort_custom(func(a, b): return int(a) < int(b))
    animation_correction_label.text = "CORRECTION OVERLAY: %s • frame %d • saved keys %s" % [
        clip_key,
        _current_pose_frame(),
        "none" if frames.is_empty() else ", ".join(frames),
    ]

func _snap_selected_bone_to_collision(contact_type: String) -> void:
    if skeleton == null or selected_pose_bone.is_empty():
        status_label.text = "Select a skeleton joint before snapping it to a surface."
        return
    var bone_index := skeleton.find_bone(selected_pose_bone)
    if bone_index < 0:
        return
    _pause_for_pose_edit()
    _apply_bone_rot_overrides()
    skeleton.force_update_all_bone_transforms()
    var bone_skeleton_position := skeleton.get_bone_global_pose(bone_index).origin
    var bone_world_position := skeleton.global_transform * bone_skeleton_position
    var directions: Array[Vector3] = [Vector3.DOWN]
    if contact_type == "wall":
        directions = [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
    var closest_hit: Dictionary = {}
    var closest_distance := INF
    var world := get_world_3d()
    if world == null:
        return
    for direction in directions:
        var query := PhysicsRayQueryParameters3D.create(
            bone_world_position - direction * 0.05,
            bone_world_position + direction * 1.5
        )
        var hit := world.direct_space_state.intersect_ray(query)
        if not hit.is_empty():
            var distance := bone_world_position.distance_to(hit.get("position", bone_world_position))
            if distance < closest_distance:
                closest_distance = distance
                closest_hit = hit
    if closest_hit.is_empty():
        status_label.text = "No %s collision is close enough to this joint." % contact_type
        return
    var target_world: Vector3 = closest_hit.get("position", bone_world_position)
    var target_skeleton := skeleton.global_transform.affine_inverse() * target_world
    var skeleton_delta := target_skeleton - bone_skeleton_position
    var parent_index := skeleton.get_bone_parent(bone_index)
    var local_delta := skeleton_delta
    if parent_index >= 0:
        local_delta = skeleton.get_bone_global_pose(parent_index).basis.inverse() * skeleton_delta
    var current_offset: Vector3 = bone_pos_offsets.get(selected_pose_bone, Vector3.ZERO)
    bone_pos_offsets[selected_pose_bone] = current_offset + local_delta
    pose_contacts[contact_type] = {
        "bone": selected_pose_bone,
        "position": target_world,
        "normal": closest_hit.get("normal", Vector3.UP),
    }
    _apply_bone_rot_overrides()
    _sync_pose_sliders_from_selection()
    _refresh_pose_keyframe_label()
    status_label.text = "Snapped %s to the nearest %s collision. Capture Pose to store the contact." % [selected_pose_bone, contact_type]
