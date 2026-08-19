extends "res://scripts/labs/animation_studio/animation_studio_model.gd"

func _process(delta: float) -> void:
    if active_editor_page != "Pose" and not dragging and not panning and active_dragged_bone == "":
        orbit_yaw += delta * 0.04
    _update_camera()
    _update_ui_state()
    _update_assembly_playhead()
    if active_editor_page == "Build" and build_waiting_for_clip:
        if animation_player and animation_player.is_playing():
            animation_player.stop()
        if skeleton:
            skeleton.clear_bones_global_pose_override()
            skeleton.reset_bone_poses()
    elif active_editor_page != "Build":
        _apply_two_hand_ik()
        _apply_bone_rot_overrides()
    _update_skeleton_chain_visual()
    _update_bubble_positions()
    _update_pose_transform_gizmo()

func _rebuild_limb_bubbles() -> void:
    for b in bubble_nodes.values():
        if is_instance_valid(b["node"]):
            b["node"].queue_free()
    bubble_nodes.clear()

    if skeleton == null:
        return

    _ensure_skeleton_chain_visual()
    _ensure_pose_transform_gizmo()

    # Direct-manipulation landmarks. The small rendered node is separate from
    # its generous screen-space picking radius, so joints remain easy to grab
    # without covering the operator.
    var landmarks := {
        "HEAD": {"names": ["mixamorig_Head", "mixamorig:Head", "head"], "color": Color(1.0, 0.85, 0.2, 0.95), "radius": 0.040},
        "NECK": {"names": ["mixamorig_Neck", "mixamorig:Neck", "neck"], "color": Color(0.45, 1.0, 0.55, 0.95), "radius": 0.032},
        "CHEST": {"names": ["mixamorig_Spine2", "mixamorig:Spine2", "Spineupper"], "color": Color(0.45, 1.0, 0.55, 0.95), "radius": 0.040},
        "SPINE": {"names": ["mixamorig_Spine1", "mixamorig:Spine1", "Spine"], "color": Color(0.45, 1.0, 0.55, 0.95), "radius": 0.037},
        "HIPS": {"names": ["mixamorig_Hips", "mixamorig:Hips", "Spinelower"], "color": Color(1.0, 1.0, 1.0, 0.95), "radius": 0.043},
        "RIGHT_SHOULDER": {"names": ["mixamorig_RightShoulder", "mixamorig:RightShoulder", "Shoulder.R"], "color": Color(0.12, 0.9, 1.0, 0.95), "radius": 0.034},
        "LEFT_SHOULDER": {"names": ["mixamorig_LeftShoulder", "mixamorig:LeftShoulder", "Shoulder.L"], "color": Color(0.12, 0.9, 1.0, 0.95), "radius": 0.034},
        "RIGHT_ELBOW": {"names": ["mixamorig_RightForeArm", "mixamorig:RightForeArm", "ArmLower.R"], "color": Color(0.12, 0.9, 1.0, 0.95), "radius": 0.034},
        "LEFT_ELBOW": {"names": ["mixamorig_LeftForeArm", "mixamorig:LeftForeArm", "ArmLower.L"], "color": Color(0.12, 0.9, 1.0, 0.95), "radius": 0.034},
        "RIGHT_HAND": {"names": ["mixamorig_RightHand", "mixamorig:RightHand", "Hand.R.001"], "color": Color(0.1, 0.95, 0.85, 0.98), "radius": 0.037},
        "LEFT_HAND": {"names": ["mixamorig_LeftHand", "mixamorig:LeftHand", "Hand.L.001"], "color": Color(0.2, 1.0, 0.35, 0.98), "radius": 0.037},
        "RIGHT_KNEE": {"names": ["mixamorig_RightLeg", "mixamorig:RightLeg", "LegLower.R"], "color": Color(0.2, 0.58, 1.0, 0.95), "radius": 0.035},
        "LEFT_KNEE": {"names": ["mixamorig_LeftLeg", "mixamorig:LeftLeg", "LegLower.L"], "color": Color(0.2, 0.58, 1.0, 0.95), "radius": 0.035},
        "RIGHT_FOOT": {"names": ["mixamorig_RightFoot", "mixamorig:RightFoot", "Foot.R"], "color": Color(1.0, 0.5, 0.1, 0.98), "radius": 0.037},
        "LEFT_FOOT": {"names": ["mixamorig_LeftFoot", "mixamorig:LeftFoot", "Foot.L"], "color": Color(1.0, 0.2, 0.6, 0.98), "radius": 0.037},
    }

    for landmark_id in landmarks.keys():
        var cfg: Dictionary = landmarks[landmark_id]
        var target_bone := ""
        var bone_idx := -1
        for cand in cfg["names"]:
            bone_idx = skeleton.find_bone(cand)
            if bone_idx != -1:
                target_bone = cand
                break
        
        if bone_idx != -1:
            var bubble_root := Node3D.new()
            bubble_root.name = "Bubble_" + landmark_id
            var bubble_mesh := MeshInstance3D.new()
            var sphere := SphereMesh.new()
            sphere.radius = float(cfg["radius"])
            sphere.height = float(cfg["radius"]) * 2.0
            sphere.radial_segments = 12
            sphere.rings = 6
            bubble_mesh.mesh = sphere
            var material := StandardMaterial3D.new()
            material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            material.albedo_color = cfg["color"]
            material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            material.no_depth_test = true
            bubble_mesh.material_override = material
            bubble_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            bubble_root.add_child(bubble_mesh)
            add_child(bubble_root)
            bubble_nodes[landmark_id] = {
                "node": bubble_root,
                "material": material,
                "bone_name": target_bone,
                "bone_idx": bone_idx,
                "color": cfg["color"],
                "radius": cfg["radius"]
            }

func _ensure_skeleton_chain_visual() -> void:
    if skeleton_chain_instance != null:
        return
    skeleton_chain_material = StandardMaterial3D.new()
    skeleton_chain_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    skeleton_chain_material.vertex_color_use_as_albedo = true
    skeleton_chain_material.no_depth_test = true
    skeleton_chain_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    skeleton_chain_instance = MeshInstance3D.new()
    skeleton_chain_instance.name = "SkeletonBodyChain"
    skeleton_chain_instance.mesh = skeleton_chain_mesh
    skeleton_chain_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(skeleton_chain_instance)

func _ensure_pose_transform_gizmo() -> void:
    if pose_transform_gizmo != null:
        return
    pose_transform_gizmo = TRANSFORM_GIZMO_SCRIPT.new()
    pose_transform_gizmo.name = "PoseTransformGizmo"
    pose_transform_gizmo.visible = false
    add_child(pose_transform_gizmo)

func _update_pose_transform_gizmo() -> void:
    if pose_transform_gizmo == null:
        return
    var should_show := (
        active_editor_page == "Pose"
        and bubbles_enabled
        and skeleton != null
        and not selected_pose_bone.is_empty()
    )
    pose_transform_gizmo.visible = should_show
    if not should_show:
        return
    var bone_index := skeleton.find_bone(selected_pose_bone)
    if bone_index < 0:
        pose_transform_gizmo.visible = false
        return
    var bone_global := skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)
    pose_transform_gizmo.global_position = bone_global.origin
    # Keep axes aligned to the operator rig rather than inheriting a wrist or
    # ankle's animated twist. This matches the predictable Gunsmith controls.
    pose_transform_gizmo.global_basis = skeleton.global_basis.orthonormalized()
    if camera:
        var distance_scale := clampf(camera.global_position.distance_to(bone_global.origin) / 3.4, 0.72, 1.45)
        pose_transform_gizmo.scale = Vector3.ONE * distance_scale

func _update_skeleton_chain_visual() -> void:
    if skeleton_chain_instance == null:
        return
    skeleton_chain_instance.visible = bubbles_enabled and skeleton != null
    skeleton_chain_mesh.clear_surfaces()
    if not skeleton_chain_instance.visible:
        return
    skeleton_chain_mesh.surface_begin(Mesh.PRIMITIVE_LINES, skeleton_chain_material)
    for bone_index in range(skeleton.get_bone_count()):
        var parent_index := skeleton.get_bone_parent(bone_index)
        if parent_index < 0:
            continue
        var child_global := skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)
        var parent_global := skeleton.global_transform * skeleton.get_bone_global_pose(parent_index)
        var segment_length := child_global.origin.distance_to(parent_global.origin)
        if segment_length < 0.002 or segment_length > 1.5:
            continue
        var bone_name := skeleton.get_bone_name(bone_index).to_lower()
        var color := Color(0.12, 0.9, 1.0, 0.92)
        if "spine" in bone_name or "hips" in bone_name or "neck" in bone_name:
            color = Color(0.35, 1.0, 0.45, 0.95)
        elif "leg" in bone_name or "foot" in bone_name or "toe" in bone_name:
            color = Color(0.2, 0.58, 1.0, 0.92)
        elif "head" in bone_name:
            color = Color(1.0, 0.82, 0.2, 0.95)
        if active_editor_page == "Build" and not selected_sequence_regions.has("full_body"):
            var sequence_region := _sequence_region_for_bone_name(bone_name)
            if sequence_region.is_empty() or not selected_sequence_regions.has(sequence_region):
                color = Color(0.22, 0.25, 0.3, 0.32)
            else:
                color = color.lightened(0.18)
        if skeleton.get_bone_name(bone_index) in [active_dragged_bone, selected_pose_bone]:
            color = Color.WHITE
        skeleton_chain_mesh.surface_set_color(color)
        skeleton_chain_mesh.surface_add_vertex(skeleton_chain_instance.to_local(parent_global.origin))
        skeleton_chain_mesh.surface_set_color(color)
        skeleton_chain_mesh.surface_add_vertex(skeleton_chain_instance.to_local(child_global.origin))
    skeleton_chain_mesh.surface_end()

func _sequence_region_for_bone_name(bone_name: String) -> String:
    if "leftshoulder" in bone_name or "leftarm" in bone_name or "lefthand" in bone_name or "armupper.l" in bone_name or "armlower.l" in bone_name or "hand.l" in bone_name:
        return "left_arm"
    if "rightshoulder" in bone_name or "rightarm" in bone_name or "righthand" in bone_name or "armupper.r" in bone_name or "armlower.r" in bone_name or "hand.r" in bone_name:
        return "right_arm"
    if "neck" in bone_name or "head" in bone_name or "eye" in bone_name:
        return "head"
    if "spine" in bone_name and not "spinelower" in bone_name:
        return "torso"
    if "hips" in bone_name or "spinelower" in bone_name or "leg" in bone_name or "foot" in bone_name or "toe" in bone_name:
        return "lower_body"
    return ""

func _update_bubble_positions() -> void:
    if not bubbles_enabled or skeleton == null:
        for b in bubble_nodes.values():
            if is_instance_valid(b["node"]):
                b["node"].visible = false
        return

    for landmark_id in bubble_nodes.keys():
        var b: Dictionary = bubble_nodes[landmark_id]
        var node: Node3D = b["node"]
        if is_instance_valid(node):
            node.visible = bubbles_enabled
            var bone_global_trans := skeleton.global_transform * skeleton.get_bone_global_pose(b["bone_idx"])
            node.global_position = bone_global_trans.origin
            var is_selected: bool = b["bone_name"] in [selected_pose_bone, active_dragged_bone]
            node.scale = Vector3.ONE * (1.55 if is_selected else 1.0)
            var material: StandardMaterial3D = b.get("material")
            if material:
                material.albedo_color = Color.WHITE if is_selected else b["color"]

func _apply_bone_rot_overrides() -> void:
    if skeleton == null:
        return
    var edited_bones: Dictionary = {}
    for bone_name in bone_rot_offsets.keys():
        edited_bones[bone_name] = true
    for bone_name in bone_pos_offsets.keys():
        edited_bones[bone_name] = true
    for bone_name in edited_bones.keys():
        var b_idx := skeleton.find_bone(bone_name)
        if b_idx != -1:
            if not bone_edit_base_poses.has(bone_name):
                _capture_bone_edit_base(bone_name)
            var pose: Transform3D = (
                skeleton.get_bone_pose(b_idx)
                if is_playing
                else bone_edit_base_poses[bone_name]
            )
            var deg: Vector3 = bone_rot_offsets.get(bone_name, Vector3.ZERO)
            var position: Vector3 = bone_pos_offsets.get(bone_name, Vector3.ZERO)
            var rad := Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z))
            var add_basis := Basis.from_euler(rad)
            pose.basis = pose.basis * add_basis
            pose.origin += position
            skeleton.set_bone_pose(b_idx, pose)

func _capture_bone_edit_base(bone_name: String, replace_existing: bool = false) -> void:
    if skeleton == null or bone_name.is_empty():
        return
    if bone_edit_base_poses.has(bone_name) and not replace_existing:
        return
    var bone_idx := skeleton.find_bone(bone_name)
    if bone_idx < 0:
        return
    bone_edit_base_poses[bone_name] = skeleton.get_bone_pose(bone_idx)
    if not bone_rot_offsets.has(bone_name):
        bone_rot_offsets[bone_name] = Vector3.ZERO
    if not bone_pos_offsets.has(bone_name):
        bone_pos_offsets[bone_name] = Vector3.ZERO

func _capture_all_edit_bases_after_seek() -> void:
    if skeleton == null:
        return
    for bone_name in bone_edit_base_poses.keys():
        var bone_idx := skeleton.find_bone(bone_name)
        if bone_idx >= 0:
            bone_edit_base_poses[bone_name] = skeleton.get_bone_pose(bone_idx)

func _pause_for_pose_edit() -> void:
    if animation_player == null:
        return
    if animation_player.is_playing():
        var current_time := animation_player.current_animation_position
        animation_player.pause()
        animation_player.seek(current_time, true)
    is_playing = false
    _capture_all_edit_bases_after_seek()

func _toggle_pose_edit_mode() -> void:
    _set_pose_edit_mode(&"MOVE" if pose_edit_mode == &"ROTATE" else &"ROTATE")

func _set_pose_edit_mode(next_mode: StringName) -> void:
    pose_edit_mode = next_mode
    if pose_tool_button != null:
        pose_tool_button.text = "Bone Tool (M): %s" % pose_edit_mode

func _human_rotation_limits(bone_name: String) -> Vector3:
    var lower := bone_name.to_lower()
    var shared_joint := _shared_upper_body_joint_name(lower)
    if shared_joint != &"":
        return PROCEDURAL_POSE_PROFILE.JOINT_AXIS_LIMITS.get(
            shared_joint,
            Vector3(20.0, 20.0, 20.0)
        )
    if "forearm" in lower or "armlower" in lower:
        return Vector3(145.0, 32.0, 40.0)
    if "arm" in lower or "shoulder" in lower:
        return Vector3(105.0, 100.0, 95.0)
    if "leglower" in lower or lower.ends_with("rightleg") or lower.ends_with("leftleg"):
        return Vector3(145.0, 24.0, 28.0)
    if "upleg" in lower or "upperleg" in lower:
        return Vector3(115.0, 55.0, 55.0)
    if "foot" in lower or "toe" in lower:
        return Vector3(55.0, 30.0, 25.0)
    if "head" in lower or "neck" in lower:
        return Vector3(55.0, 75.0, 45.0)
    if "spine" in lower or "chest" in lower:
        return Vector3(45.0, 60.0, 40.0)
    if "hand" in lower:
        return Vector3(70.0, 45.0, 80.0)
    if "hips" in lower:
        return Vector3(35.0, 55.0, 35.0)
    return Vector3(75.0, 75.0, 75.0)

func _shared_upper_body_joint_name(lower_bone_name: String) -> StringName:
    if "forearm" in lower_bone_name or "armlower" in lower_bone_name:
        return &"left_forearm" if "left" in lower_bone_name or ".l" in lower_bone_name else &"right_forearm"
    if "shoulder" in lower_bone_name:
        return &"left_shoulder" if "left" in lower_bone_name or ".l" in lower_bone_name else &"right_shoulder"
    if "arm" in lower_bone_name and not "hand" in lower_bone_name:
        return &"left_upper_arm" if "left" in lower_bone_name or ".l" in lower_bone_name else &"right_upper_arm"
    if "head" in lower_bone_name:
        return &"head"
    if "neck" in lower_bone_name:
        return &"neck"
    if "spine2" in lower_bone_name or "spineupper" in lower_bone_name:
        return &"spine2"
    if "spine1" in lower_bone_name:
        return &"spine1"
    if "spine" in lower_bone_name and not "spinelower" in lower_bone_name:
        return &"spine"
    return &""

func _clamp_human_rotation(bone_name: String, rotation_degrees: Vector3) -> Vector3:
    var limits := _human_rotation_limits(bone_name)
    return Vector3(
        clampf(rotation_degrees.x, -limits.x, limits.x),
        clampf(rotation_degrees.y, -limits.y, limits.y),
        clampf(rotation_degrees.z, -limits.z, limits.z)
    )

func _anatomical_drag_chain(bone_name: String) -> Array[String]:
    var result: Array[String] = []
    if skeleton == null:
        return result
    var selected_index := skeleton.find_bone(bone_name)
    if selected_index < 0:
        return result
    var lower := bone_name.to_lower()
    if not pose_follow_chain and not ("hips" in lower or "root" in lower):
        result.append(bone_name)
        return result
    var driver_index := selected_index
    # End effectors move through their upstream joints. This preserves the
    # authored bone lengths instead of stretching a hand or foot away from its
    # arm/leg.
    if "hand" in lower or "foot" in lower or "head" in lower or "neck" in lower:
        driver_index = skeleton.get_bone_parent(selected_index)
    elif (
        "forearm" in lower
        or "armlower" in lower
        or "leglower" in lower
        or lower.ends_with("rightleg")
        or lower.ends_with("leftleg")
    ):
        driver_index = skeleton.get_bone_parent(selected_index)
    if driver_index >= 0:
        result.append(skeleton.get_bone_name(driver_index))
        var parent_index := skeleton.get_bone_parent(driver_index)
        if parent_index >= 0 and ("hand" in lower or "foot" in lower):
            result.append(skeleton.get_bone_name(parent_index))
    if result.is_empty() and not ("hips" in lower or "root" in lower):
        result.append(bone_name)
    return result

func _begin_anatomical_drag(bone_name: String) -> void:
    drag_rotation_chain = _anatomical_drag_chain(bone_name)
    drag_start_rotations.clear()
    drag_start_local_offset = bone_pos_offsets.get(bone_name, Vector3.ZERO)
    _capture_bone_edit_base(bone_name)
    drag_start_rotations[bone_name] = bone_rot_offsets.get(bone_name, Vector3.ZERO)
    for driver_bone in drag_rotation_chain:
        _capture_bone_edit_base(driver_bone)
        drag_start_rotations[driver_bone] = bone_rot_offsets.get(driver_bone, Vector3.ZERO)

func _drag_anatomical_chain(mouse_delta_from_start: Vector2) -> void:
    for chain_index in range(drag_rotation_chain.size()):
        var driver_bone := drag_rotation_chain[chain_index]
        var start_rotation: Vector3 = drag_start_rotations.get(driver_bone, Vector3.ZERO)
        var influence := 1.0 if chain_index == 0 else 0.55
        var requested := start_rotation + Vector3(
            -mouse_delta_from_start.y * 0.32 * influence,
            mouse_delta_from_start.x * 0.30 * influence,
            mouse_delta_from_start.x * 0.10 * influence
        )
        bone_rot_offsets[driver_bone] = _clamp_human_rotation(driver_bone, requested)

func _gizmo_drag_scalar(axis: StringName, mouse_delta_from_start: Vector2) -> float:
    if axis == &"y":
        return -mouse_delta_from_start.y
    return mouse_delta_from_start.x

func _drag_selected_rotation_axis(axis: StringName, mouse_delta_from_start: Vector2) -> void:
    if active_dragged_bone.is_empty():
        return
    var requested: Vector3 = drag_start_rotations.get(active_dragged_bone, Vector3.ZERO)
    var amount := _gizmo_drag_scalar(axis, mouse_delta_from_start) * 0.35
    if axis == &"x":
        requested.x += amount
    elif axis == &"y":
        requested.y += amount
    else:
        requested.z += amount
    var previous: Vector3 = drag_start_rotations.get(active_dragged_bone, Vector3.ZERO)
    var safe := _clamp_human_rotation(active_dragged_bone, requested)
    bone_rot_offsets[active_dragged_bone] = safe
    _apply_rotation_continuation(active_dragged_bone, safe - previous, true)

func _apply_rotation_continuation(
    bone_name: String,
    delta_degrees: Vector3,
    from_drag_start: bool = false
) -> void:
    if skeleton == null or not pose_follow_chain:
        return
    var lower := bone_name.to_lower()
    var parent_index := skeleton.get_bone_parent(skeleton.find_bone(bone_name))
    if parent_index < 0:
        return
    var parent_name := String(skeleton.get_bone_name(parent_index))
    var influence := 0.0
    if "head" in lower:
        influence = 0.35
    elif "neck" in lower:
        influence = 0.18
    elif ("arm" in lower and not "forearm" in lower and not "armlower" in lower):
        influence = 0.20
    elif "spine2" in lower or "spineupper" in lower:
        influence = 0.35
    if influence <= 0.0:
        return
    _capture_bone_edit_base(parent_name)
    var parent_rotation: Vector3 = (
        drag_start_rotations.get(parent_name, bone_rot_offsets.get(parent_name, Vector3.ZERO))
        if from_drag_start
        else bone_rot_offsets.get(parent_name, Vector3.ZERO)
    )
    bone_rot_offsets[parent_name] = _clamp_human_rotation(
        parent_name,
        parent_rotation + delta_degrees * influence
    )

func _drag_selected_translation_axis(axis: StringName, mouse_delta_from_start: Vector2) -> void:
    if active_dragged_bone.is_empty():
        return
    var lower_name := active_dragged_bone.to_lower()
    if "hips" in lower_name or "root" in lower_name:
        var requested := drag_start_local_offset
        var amount := _gizmo_drag_scalar(axis, mouse_delta_from_start) * translation_meters_per_pixel
        if axis == &"x":
            requested.x = clampf(drag_start_local_offset.x + amount, -0.35, 0.35)
        elif axis == &"y":
            requested.y = clampf(drag_start_local_offset.y + amount, -0.35, 0.35)
        else:
            requested.z = clampf(drag_start_local_offset.z + amount, -0.35, 0.35)
        bone_pos_offsets[active_dragged_bone] = requested
        return

    # Limbs never translate away from their parent. An arrow drives the
    # upstream anatomical chain, preserving every authored bone length.
    var amount := _gizmo_drag_scalar(axis, mouse_delta_from_start)
    for chain_index in range(drag_rotation_chain.size()):
        var driver_bone := drag_rotation_chain[chain_index]
        var requested: Vector3 = drag_start_rotations.get(driver_bone, Vector3.ZERO)
        var influence := 1.0 if chain_index == 0 else 0.55
        if axis == &"x":
            requested.y += amount * 0.30 * influence
            requested.z += amount * 0.10 * influence
        elif axis == &"y":
            requested.x += amount * 0.32 * influence
        else:
            requested.x += amount * 0.22 * influence
            requested.z -= amount * 0.22 * influence
        bone_rot_offsets[driver_bone] = _clamp_human_rotation(driver_bone, requested)

func _apply_two_hand_ik() -> void:
    if not two_hand_ik_enabled or skeleton == null or left_hand_marker == null or current_weapon == WeaponType.NONE:
        return
    # Skip IK on scaled models — the target positions don't match
    if model_root and model_root.scale.x > 1.5:
        return
    
    var left_hand_idx := skeleton.find_bone("mixamorig_LeftHand")
    if left_hand_idx == -1: left_hand_idx = skeleton.find_bone("mixamorig:LeftHand")
    if left_hand_idx == -1: left_hand_idx = skeleton.find_bone("Hand.L.001")
    if left_hand_idx == -1: return

    var target_global_pos := left_hand_marker.global_position
    var target_in_skel := skeleton.global_transform.affine_inverse() * target_global_pos
    var current_hand_pose := skeleton.get_bone_global_pose(left_hand_idx)
    
    var blend_pos := current_hand_pose.origin.lerp(target_in_skel, 0.85 * two_hand_ik_weight)
    current_hand_pose.origin = blend_pos
    skeleton.set_bone_global_pose_override(left_hand_idx, current_hand_pose, 0.85 * two_hand_ik_weight, true)

func _update_ui_state() -> void:
    if animation_player == null or filtered_entries.is_empty():
        return
    
    var entry: Dictionary = filtered_entries[clip_index]
    var anim: Animation = _get_current_animation(entry)
    var length: float = anim.length if anim else 1.0
    var current_pos: float = (
        animation_player.current_animation_position
        if not animation_player.current_animation.is_empty()
        else 0.0
    )
    var displayed_source_pos := trim_in_seconds + current_pos if trim_preview_active else current_pos
    
    if not timeline_slider.has_focus():
        timeline_slider.max_value = length
        timeline_slider.set_value_no_signal(displayed_source_pos)
    
    var current_frame := clampi(roundi(displayed_source_pos * EDITOR_FPS), 0, maxi(1, roundi(length * EDITOR_FPS)))
    var total_frames := maxi(1, roundi(length * EDITOR_FPS))
    timeline_slider.step = 1.0 / EDITOR_FPS
    timeline_slider.tick_count = total_frames + 1
    timeline_slider.ticks_on_borders = true
    if range_selector:
        range_selector.set_playhead(displayed_source_pos)
    time_label.text = "Frame %d / %d  •  %.2fs / %.2fs" % [current_frame, total_frames, displayed_source_pos, length]
    _refresh_frame_editor_labels()
    
    var skin_name := _skin_name(current_skin)
    var wep_name := _weapon_name(current_weapon)
    status_label.text = (
        "[ REST POSE ]  •  Drag clips from the library onto the T-pose body map"
        if active_editor_page == "Body"
        else "[ %s ]  •  Weapon: %s  •  Clip %d/%d: %s (%.2fs)" % [
            skin_name,
            wep_name,
            clip_index + 1,
            filtered_entries.size(),
            entry["display"],
            length
        ]
    )

    if active_dragged_bone != "":
        limb_hud_label.visible = true
        var deg: Vector3 = bone_rot_offsets.get(active_dragged_bone, Vector3.ZERO)
        var pos: Vector3 = bone_pos_offsets.get(active_dragged_bone, Vector3.ZERO)
        limb_hud_label.text = (
            "%s [%s]  ROT %.1f°, %.1f°, %.1f°  POS %.3f, %.3f, %.3f m"
            % [pose_edit_mode, active_dragged_bone, deg.x, deg.y, deg.z, pos.x, pos.y, pos.z]
        )
    else:
        limb_hud_label.visible = false

func _get_current_animation(entry: Dictionary) -> Animation:
    if entry["type"] == "BAKED":
        return animation_player.get_animation(entry["name"]) if animation_player else null
    elif dynamic_anim_lib and entry.has("key"):
        var anim_key: StringName = StringName(entry["key"])
        if dynamic_anim_lib.has_animation(anim_key):
            return dynamic_anim_lib.get_animation(anim_key)
    return null
