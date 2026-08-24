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
    _sync_animation_preview_weapon_parent()
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
