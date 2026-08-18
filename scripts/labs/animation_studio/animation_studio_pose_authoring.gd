extends "res://scripts/labs/animation_studio/animation_studio_pose_runtime.gd"

func _unhandled_input(event: InputEvent) -> void:
    # Some full-window 3D controls can claim an otherwise valid drawer click.
    # Treat the visible handle as authoritative before orbit input begins.
    if (
        event is InputEventMouseButton
        and event.button_index == MOUSE_BUTTON_LEFT
        and event.pressed
        and sequence_drawer_button != null
        and sequence_drawer_button.visible
        and sequence_drawer_button.get_global_rect().has_point(event.position)
    ):
        _toggle_sequence_drawer()
        get_viewport().set_input_as_handled()
        return
    if event is InputEventKey and event.pressed and not event.echo:
        match event.physical_keycode:
            KEY_LEFT:
                _select_relative(-1)
            KEY_RIGHT:
                _select_relative(1)
            KEY_SPACE:
                _toggle_play_pause()
            KEY_TAB:
                _toggle_skin()
            KEY_G:
                _cycle_weapon()
            KEY_B:
                _toggle_bubbles()
            KEY_M:
                _toggle_pose_edit_mode()
            KEY_L:
                _toggle_gun_lab()
            KEY_R:
                _reset_camera()
            KEY_C:
                _clear_bone_rot_offsets()
            KEY_1:
                _assign_to_slot("idle_rifle")
            KEY_2:
                _assign_to_slot("run_forward")
            KEY_3:
                _assign_to_slot("run_backward")
            KEY_4:
                _assign_to_slot("jump_loop")
            KEY_5:
                _assign_to_slot("dive_roll")
            KEY_6:
                _assign_to_slot("prone_backward")
            KEY_ESCAPE:
                get_tree().quit()

    elif event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                var gizmo_handle: StringName = &""
                if pose_transform_gizmo and active_editor_page == "Pose":
                    gizmo_handle = pose_transform_gizmo.pick(camera, event.position)
                if gizmo_handle != &"" and not selected_pose_bone.is_empty():
                    _pause_for_pose_edit()
                    active_pose_gizmo_handle = gizmo_handle
                    active_dragged_bone = selected_pose_bone
                    drag_start_mouse = event.position
                    drag_origin_mouse = event.position
                    _begin_anatomical_drag(active_dragged_bone)
                    pose_transform_gizmo.set_hovered(gizmo_handle)
                    get_viewport().set_input_as_handled()
                    return
                # A body node only selects the joint. Editing begins from an
                # explicit XYZ arrow or rotation ring, never from free drag.
                var clicked_bone := _find_bubble_at_mouse(event.position)
                if clicked_bone != "":
                    _pause_for_pose_edit()
                    _select_pose_bone(clicked_bone)
                    active_dragged_bone = ""
                    active_pose_gizmo_handle = &""
                    get_viewport().set_input_as_handled()
                    return
                else:
                    dragging = true
            else:
                dragging = false
                active_dragged_bone = ""
                active_pose_gizmo_handle = &""
                _sync_pose_sliders_from_selection()

        elif event.button_index == MOUSE_BUTTON_RIGHT:
            panning = event.pressed
        elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
            orbit_distance = maxf(1.4, orbit_distance - 0.25)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
            orbit_distance = minf(7.5, orbit_distance + 0.25)

    elif event is InputEventMouseMotion:
        if active_dragged_bone != "" and active_pose_gizmo_handle != &"":
            var total_drag: Vector2 = event.position - drag_origin_mouse
            drag_start_mouse = event.position
            var axis := pose_transform_gizmo.axis_name(active_pose_gizmo_handle)
            if pose_transform_gizmo.is_rotation(active_pose_gizmo_handle):
                _drag_selected_rotation_axis(axis, total_drag)
            else:
                _drag_selected_translation_axis(axis, total_drag)
            _apply_bone_rot_overrides()
            _sync_pose_sliders_from_selection()
        elif dragging:
            orbit_yaw -= event.relative.x * 0.007
            orbit_pitch = clampf(orbit_pitch - event.relative.y * 0.005, -0.65, 0.45)
        elif panning:
            target_height = clampf(target_height + event.relative.y * 0.004, 0.2, 1.8)
        elif pose_transform_gizmo and active_editor_page == "Pose":
            pose_transform_gizmo.set_hovered(pose_transform_gizmo.pick(camera, event.position))

func _find_bubble_at_mouse(m_pos: Vector2) -> String:
    if not bubbles_enabled or camera == null:
        return ""
    var closest_dist := 36.0 # pixel hit radius
    var selected_bone := ""
    
    for landmark_id in bubble_nodes.keys():
        var b: Dictionary = bubble_nodes[landmark_id]
        var node: Node3D = b["node"]
        if is_instance_valid(node) and not camera.is_position_behind(node.global_position):
            var screen_pos := camera.unproject_position(node.global_position)
            var d := screen_pos.distance_to(m_pos)
            if d < closest_dist:
                closest_dist = d
                selected_bone = b["bone_name"]
    return selected_bone

func _toggle_bubbles() -> void:
    bubbles_enabled = not bubbles_enabled
    bubbles_toggle_btn.text = "Skeleton Chain (B): " + ("ON" if bubbles_enabled else "OFF")

func _clear_bone_rot_offsets() -> void:
    if skeleton != null:
        for bone_name in bone_edit_base_poses.keys():
            var bone_idx := skeleton.find_bone(bone_name)
            if bone_idx >= 0:
                skeleton.set_bone_pose(bone_idx, bone_edit_base_poses[bone_name])
    bone_rot_offsets.clear()
    bone_pos_offsets.clear()
    bone_edit_base_poses.clear()
    _sync_pose_sliders_from_selection()

func _prepare_pose_mode() -> void:
    if animation_player == null or skeleton == null:
        return
    build_waiting_for_clip = false
    _set_pose_edit_mode(&"MOVE")
    if animation_player.current_animation.is_empty() and not filtered_entries.is_empty():
        _play_selected()
    _pause_for_pose_edit()
    if weapon_node:
        weapon_node.visible = current_weapon != WeaponType.NONE
    if selected_pose_bone.is_empty() and not bubble_nodes.is_empty():
        var first_landmark := String(bubble_nodes.keys()[0])
        selected_pose_bone = String((bubble_nodes[first_landmark] as Dictionary).get("bone_name", ""))
    if not selected_pose_bone.is_empty():
        _capture_bone_edit_base(selected_pose_bone)
    _sync_pose_sliders_from_selection()
    _refresh_pose_keyframe_label()

func _select_pose_bone(bone_name: String) -> void:
    if bone_name.is_empty():
        return
    selected_pose_bone = bone_name
    _capture_bone_edit_base(bone_name)
    _sync_pose_sliders_from_selection()
    _update_skeleton_chain_visual()

func _sync_pose_sliders_from_selection() -> void:
    if pose_selected_bone_label:
        pose_selected_bone_label.text = (
            "SELECTED JOINT: %s" % selected_pose_bone.replace("mixamorig_", "").replace("mixamorig:", "")
            if not selected_pose_bone.is_empty()
            else "SELECTED JOINT: click a cyan skeleton node"
        )
    if pose_slider_controls.is_empty():
        return
    pose_slider_syncing = true
    var position: Vector3 = bone_pos_offsets.get(selected_pose_bone, Vector3.ZERO)
    var rotation: Vector3 = bone_rot_offsets.get(selected_pose_bone, Vector3.ZERO)
    var selected_lower := selected_pose_bone.to_lower()
    var root_can_translate := "hips" in selected_lower or "root" in selected_lower
    var values := {
        "move_x": position.x,
        "move_y": position.y,
        "move_z": position.z,
        "rot_x": rotation.x,
        "rot_y": rotation.y,
        "rot_z": rotation.z,
    }
    for key in values.keys():
        if pose_slider_controls.has(key):
            var slider: HSlider = pose_slider_controls[key]["slider"]
            var value_label: Label = pose_slider_controls[key]["label"]
            slider.editable = root_can_translate if String(key).begins_with("move_") else true
            slider.value = float(values[key])
            value_label.text = (
                _pose_slider_value_text(String(key), float(values[key]))
                if slider.editable
                else "chain locked"
            )
    pose_slider_syncing = false

func _pose_slider_value_text(key: String, value: float) -> String:
    return "%.1f°" % value if key.begins_with("rot_") else "%.1f cm" % (value * 100.0)

func _set_pose_slider_value(key: String, value: float) -> void:
    if pose_slider_syncing or selected_pose_bone.is_empty():
        return
    _pause_for_pose_edit()
    _capture_bone_edit_base(selected_pose_bone)
    if key.begins_with("move_"):
        var selected_lower := selected_pose_bone.to_lower()
        if not ("hips" in selected_lower or "root" in selected_lower):
            status_label.text = "Limb length protected: drag this node to rotate its anatomical chain instead of stretching the bone."
            _sync_pose_sliders_from_selection()
            return
        var position: Vector3 = bone_pos_offsets.get(selected_pose_bone, Vector3.ZERO)
        match key:
            "move_x": position.x = value
            "move_y": position.y = value
            "move_z": position.z = value
        bone_pos_offsets[selected_pose_bone] = position
    else:
        var rotation: Vector3 = bone_rot_offsets.get(selected_pose_bone, Vector3.ZERO)
        match key:
            "rot_x": rotation.x = value
            "rot_y": rotation.y = value
            "rot_z": rotation.z = value
        bone_rot_offsets[selected_pose_bone] = _clamp_human_rotation(selected_pose_bone, rotation)
    if pose_slider_controls.has(key):
        var value_label: Label = pose_slider_controls[key]["label"]
        value_label.text = _pose_slider_value_text(key, value)
    _apply_bone_rot_overrides()
    if skeleton:
        skeleton.force_update_all_bone_transforms()

func _current_pose_frame() -> int:
    if animation_player == null or animation_player.current_animation.is_empty():
        return 0
    return maxi(0, roundi(animation_player.current_animation_position * EDITOR_FPS))

func _capture_pose_keyframe() -> void:
    if skeleton == null:
        return
    _pause_for_pose_edit()
    _apply_bone_rot_overrides()
    skeleton.force_update_all_bone_transforms()
    var frame := _current_pose_frame()
    pose_editor.capture_pose(skeleton, frame, pose_contacts)
    _refresh_pose_keyframe_label()
    status_label.text = "Captured the complete edited skeleton at frame %d. The source animation is unchanged." % frame

func _duplicate_latest_pose() -> void:
    if skeleton == null:
        return
    if pose_editor.keyframes.is_empty():
        _capture_pose_keyframe()
        return
    var source_index: int = pose_editor.keyframes.size() - 1
    var target_frame := int(pose_editor.keyframes[source_index].get("frame", 0)) + 1
    var selected_animation := _selected_animation()
    if animation_player and selected_animation:
        animation_player.seek(minf(float(target_frame) / EDITOR_FPS, selected_animation.length), true)
    bone_rot_offsets.clear()
    bone_pos_offsets.clear()
    bone_edit_base_poses.clear()
    pose_editor.apply_keyframe(skeleton, source_index)
    pose_editor.capture_pose(skeleton, target_frame, pose_contacts)
    _capture_all_edit_bases_after_seek()
    _sync_pose_sliders_from_selection()
    _refresh_pose_keyframe_label()
    status_label.text = "Duplicated the previous pose to frame %d. Adjust a joint, then capture again." % target_frame

func _copy_latest_pose() -> void:
    if pose_editor.copy_latest_pose():
        status_label.text = "Copied the latest complete body pose."
    else:
        status_label.text = "Capture a pose before copying it."

func _paste_pose_to_current_frame() -> void:
    if skeleton == null or not pose_editor.paste_pose(skeleton):
        status_label.text = "Copy a captured pose before pasting it."
        return
    bone_rot_offsets.clear()
    bone_pos_offsets.clear()
    bone_edit_base_poses.clear()
    _capture_all_edit_bases_after_seek()
    _sync_pose_sliders_from_selection()
    status_label.text = "Pasted the copied pose. Press Capture Pose to keep it at this frame."

func _pose_skeleton_path() -> NodePath:
    if animation_player == null or skeleton == null:
        return NodePath("")
    var animation_root := animation_player.get_node_or_null(animation_player.root_node)
    if animation_root == null:
        return NodePath("")
    return animation_root.get_path_to(skeleton)

func _build_pose_animation() -> Animation:
    return pose_editor.build_animation(_pose_skeleton_path(), EDITOR_FPS, pose_smooth_interpolation)

func _preview_pose_strip() -> void:
    var animation := _build_pose_animation()
    if animation == null or animation_player == null:
        status_label.text = "Capture at least one pose before previewing."
        return
    var preview_key := StringName("pose_strip_preview")
    if dynamic_anim_lib.has_animation(preview_key):
        dynamic_anim_lib.remove_animation(preview_key)
    dynamic_anim_lib.add_animation(preview_key, animation)
    bone_rot_offsets.clear()
    bone_pos_offsets.clear()
    bone_edit_base_poses.clear()
    skeleton.reset_bone_poses()
    animation_player.play(StringName("dyn/" + String(preview_key)))
    animation_player.speed_scale = playback_speed
    is_playing = true
    status_label.text = "Playing %d captured key poses with %s interpolation." % [
        pose_editor.keyframes.size(),
        "smooth" if pose_smooth_interpolation else "held stop-motion",
    ]

func _save_pose_strip() -> void:
    var animation := _build_pose_animation()
    if animation == null:
        status_label.text = "Capture at least one pose before saving."
        return
    var requested_name := pose_name_input.text.strip_edges() if pose_name_input else ""
    if requested_name.is_empty():
        requested_name = "stop_motion_pose"
    if authored_name_input:
        authored_name_input.text = requested_name
    var baked_pose: Array[Dictionary] = [{
        "animation": animation,
        "start": 0.0,
        "end": animation.length,
        "display": requested_name,
        "path": "",
    }]
    _save_authored_segments(baked_pose, requested_name.to_snake_case(), false)

func _clear_pose_strip() -> void:
    pose_editor.clear()
    pose_contacts.clear()
    _refresh_pose_keyframe_label()
    status_label.text = "Cleared captured key poses. Imported source animations were not changed."

func _toggle_pose_interpolation() -> void:
    pose_smooth_interpolation = not pose_smooth_interpolation
    if pose_interpolation_button:
        pose_interpolation_button.text = "Between Poses: %s" % (
            "SMOOTH" if pose_smooth_interpolation else "HOLD"
        )

func _refresh_pose_keyframe_label() -> void:
    if pose_keyframe_label:
        pose_keyframe_label.text = pose_editor.summary()
    if pose_contact_summary_label:
        pose_contact_summary_label.text = "CONTACTS: %s" % (
            "none" if pose_contacts.is_empty() else ", ".join(pose_contacts.keys())
        )

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
