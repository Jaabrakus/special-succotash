extends "res://scripts/labs/animation_studio/animation_studio_pose_runtime.gd"


func _on_animation_stage_gui_input(event: InputEvent) -> void:
    _handle_animation_studio_input(event)


func _unhandled_input(event: InputEvent) -> void:
    # Keyboard shortcuts remain unhandled so text fields and editor controls
    # get first refusal. Pointer events are owned by the stage input surface.
    if event is InputEventKey:
        _handle_animation_studio_input(event)


func _handle_animation_studio_input(event: InputEvent) -> void:
    if event is InputEventMouse and _pointer_over_animation_editor_ui(event.position):
        if event is InputEventMouseButton and not event.pressed:
            _cancel_animation_rig_pointer()
        return
    if event is InputEventKey and _text_editor_has_focus():
        return
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
                if (
                    gizmo_handle != &""
                    and (
                        not selected_pose_bone.is_empty()
                        or not animation_rig_selected_target.is_empty()
                    )
                ):
                    _pause_for_pose_edit()
                    active_pose_gizmo_handle = gizmo_handle
                    drag_start_mouse = event.position
                    drag_origin_mouse = event.position
                    if not animation_rig_selected_target.is_empty():
                        animation_rig_active_drag_target = animation_rig_selected_target
                        _begin_animation_rig_target_drag(animation_rig_active_drag_target)
                    else:
                        active_dragged_bone = selected_pose_bone
                        _begin_anatomical_drag(active_dragged_bone)
                    pose_transform_gizmo.set_hovered(gizmo_handle)
                    get_viewport().set_input_as_handled()
                    return
                var clicked_rig_target: StringName = (
                    animation_rig_overlay.pick(camera, event.position)
                    if (
                        active_editor_page == "Pose"
                        and animation_rig_overlay
                        and animation_rig_overlay.visible
                    )
                    else &""
                )
                if clicked_rig_target != &"":
                    _pause_for_pose_edit()
                    if String(clicked_rig_target).begins_with("bone:"):
                        animation_rig_selected_target = &""
                        var direct_bone := String(clicked_rig_target).trim_prefix("bone:")
                        _select_pose_bone(direct_bone)
                        _begin_direct_bone_drag(direct_bone, event.position)
                        get_viewport().set_input_as_handled()
                        return
                    _select_animation_rig_target(clicked_rig_target)
                    if clicked_rig_target in [
                        &"right_elbow_pole", &"left_elbow_pole",
                        &"right_hand", &"left_hand",
                        &"placement_origin",
                    ]:
                        animation_rig_active_drag_target = clicked_rig_target
                        drag_origin_mouse = event.position
                        drag_start_mouse = event.position
                        active_pose_gizmo_handle = &"screen_plane"
                        _begin_animation_rig_target_drag(clicked_rig_target)
                    get_viewport().set_input_as_handled()
                    return
                # A body node only selects the joint. Editing begins from an
                # explicit XYZ arrow or rotation ring, never from free drag.
                var clicked_bone := _find_bubble_at_mouse(event.position)
                if clicked_bone != "":
                    _pause_for_pose_edit()
                    animation_rig_selected_target = &""
                    _select_pose_bone(clicked_bone)
                    _begin_direct_bone_drag(clicked_bone, event.position)
                    get_viewport().set_input_as_handled()
                    return
                else:
                    dragging = true
            else:
                dragging = false
                active_dragged_bone = ""
                _end_animation_rig_target_drag(animation_rig_active_drag_target)
                animation_rig_active_drag_target = &""
                active_pose_gizmo_handle = &""
                _sync_pose_sliders_from_selection()

        elif event.button_index == MOUSE_BUTTON_RIGHT:
            panning = event.pressed
        elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
            orbit_distance = maxf(1.4, orbit_distance - 0.25)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
            orbit_distance = minf(7.5, orbit_distance + 0.25)

    elif event is InputEventMouseMotion:
        if animation_rig_active_drag_target != &"" and active_pose_gizmo_handle != &"":
            var rig_total_drag: Vector2 = event.position - drag_origin_mouse
            if active_pose_gizmo_handle == &"screen_plane":
                _drag_animation_rig_target_screen(
                    animation_rig_active_drag_target,
                    rig_total_drag
                )
            else:
                var rig_axis := String(pose_transform_gizmo.axis_name(active_pose_gizmo_handle))
                _drag_animation_rig_target(
                    animation_rig_active_drag_target,
                    rig_axis,
                    rig_total_drag,
                    pose_transform_gizmo.is_rotation(active_pose_gizmo_handle)
                )
        elif active_dragged_bone != "" and active_pose_gizmo_handle != &"":
            var total_drag: Vector2 = event.position - drag_origin_mouse
            drag_start_mouse = event.position
            if active_pose_gizmo_handle == &"direct_joint":
                _drag_anatomical_chain(total_drag)
            else:
                var axis: String = String(pose_transform_gizmo.axis_name(active_pose_gizmo_handle))
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
            if animation_rig_overlay and animation_rig_overlay.visible:
                animation_rig_overlay.set_hovered_target(
                    animation_rig_overlay.pick(camera, event.position)
                )


func _begin_direct_bone_drag(bone_name: String, screen_position: Vector2) -> void:
    active_dragged_bone = bone_name
    active_pose_gizmo_handle = &"direct_joint"
    drag_origin_mouse = screen_position
    drag_start_mouse = screen_position
    _begin_anatomical_drag(bone_name)


func _pointer_over_animation_editor_ui(screen_position: Vector2) -> bool:
    var editor_controls: Array[Control] = [
        clip_library_panel,
        runtime_map_panel,
        frame_editor_dock,
        gun_lab_panel,
    ]
    var header := find_child("StudioHeaderPanel", true, false) as Control
    if header != null:
        editor_controls.append(header)
    for control in editor_controls:
        if (
            control != null
            and control.visible
            and control.get_global_rect().has_point(screen_position)
        ):
            return true
    return false


func _text_editor_has_focus() -> bool:
    var focused := get_viewport().gui_get_focus_owner()
    return focused is LineEdit or focused is TextEdit


func _cancel_animation_rig_pointer() -> void:
    dragging = false
    panning = false
    active_dragged_bone = ""
    animation_rig_active_drag_target = &""
    active_pose_gizmo_handle = &""

func _find_bubble_at_mouse(m_pos: Vector2) -> String:
    if not bubbles_enabled or camera == null:
        return ""
    var closest_dist := 36.0 # pixel hit radius
    var selected_bone := ""

    for landmark_id in bubble_nodes.keys():
        var b: Dictionary = bubble_nodes[landmark_id]
        var node: Node3D = b["node"]
        if (
            is_instance_valid(node)
            and node.visible
            and not camera.is_position_behind(node.global_position)
        ):
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
    bubbles_enabled = true
    if bubbles_toggle_btn:
        bubbles_toggle_btn.text = "Skeleton Chain (B): ON"
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
    # Pose mode must open on the unmodified imported animation. Corrections are
    # an explicit authoring layer; enabling them automatically replaced the
    # clean source pose with hand/weapon IK as soon as the user paused a clip.
    if animation_correction_toggle:
        animation_correction_toggle.set_pressed_no_signal(animation_correction_enabled)
    _refresh_animation_correction_label()

func _select_pose_bone(bone_name: String) -> void:
    if bone_name.is_empty():
        return
    selected_pose_bone = bone_name
    animation_rig_selected_target = &""
    if animation_rig_overlay:
        animation_rig_overlay.set_selected_target(&"")
    _capture_bone_edit_base(bone_name)
    _sync_pose_sliders_from_selection()
    _update_skeleton_chain_visual()
    if status_label:
        status_label.text = "Selected %s. XYZ edits this joint only. Turn Follow Chain on when nearby joints must help." % bone_name.replace("mixamorig_", "")

func _select_animation_rig_joint(index: int) -> void:
    if animation_rig_joint_picker == null or skeleton == null:
        return
    var joint_name := String(
        animation_rig_joint_picker.get_item_metadata(index)
    )
    for bone_index in range(skeleton.get_bone_count()):
        var bone_name := String(skeleton.get_bone_name(bone_index))
        if animation_correction_overlay.joint_name_for_bone(bone_name) == joint_name:
            _select_pose_bone(bone_name)
            if not animation_correction_enabled:
                animation_correction_toggle.set_pressed_no_signal(true)
                _toggle_animation_correction_overlay(true)
            return
    if status_label:
        status_label.text = "%s is not available on this preview skeleton." % (
            JOINT_CONTROL_SCHEMA.display_name(StringName(joint_name))
        )

func _toggle_pose_follow_chain() -> void:
    pose_follow_chain = not pose_follow_chain
    if pose_follow_chain_button:
        pose_follow_chain_button.text = "Isolated Joint: %s" % (
            "OFF" if pose_follow_chain else "ON"
        )
    if status_label:
        status_label.text = (
            "Joint isolation is OFF. Parent joints can share the adjustment."
            if pose_follow_chain
            else "Joint isolation is ON. Only this joint's correction is written; hand IK is paused."
        )

func _sync_pose_sliders_from_selection() -> void:
    if pose_selected_bone_label:
        pose_selected_bone_label.text = (
            "SELECTED JOINT: %s" % selected_pose_bone.replace("mixamorig_", "").replace("mixamorig:", "")
            if not selected_pose_bone.is_empty()
            else "SELECTED JOINT: click a cyan skeleton node"
        )
    if pose_slider_controls.is_empty():
        return
    if animation_rig_joint_picker and not selected_pose_bone.is_empty():
        var logical_joint := animation_correction_overlay.joint_name_for_bone(
            selected_pose_bone
        )
        for item_index in range(animation_rig_joint_picker.item_count):
            if String(animation_rig_joint_picker.get_item_metadata(item_index)) == logical_joint:
                animation_rig_joint_picker.select(item_index)
                break
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
        var previous_rotation := rotation
        match key:
            "rot_x": rotation.x = value
            "rot_y": rotation.y = value
            "rot_z": rotation.z = value
        var safe_rotation := _clamp_human_rotation(selected_pose_bone, rotation)
        bone_rot_offsets[selected_pose_bone] = safe_rotation
        _apply_rotation_continuation(
            selected_pose_bone,
            safe_rotation - previous_rotation
        )
    if pose_slider_controls.has(key):
        var value_label: Label = pose_slider_controls[key]["label"]
        value_label.text = _pose_slider_value_text(key, value)
    _apply_bone_rot_overrides()
    if skeleton:
        skeleton.force_update_all_bone_transforms()
