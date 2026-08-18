extends "res://scripts/labs/animation_studio/animation_studio_workspace.gd"

func _load_skin(skin: SkinType) -> void:
    if model_root:
        model_root.queue_free()
        model_root = null
    
    current_skin = skin
    
    match skin:
        SkinType.PS1_GAS_MASK_SOLDIER:
            model_root = PS1_GAS_MASK_RIGGED_SCENE.instantiate() as Node3D
            model_root.scale = Vector3.ONE * 55.0  # Mixamo exported at ~3cm tall, scale to ~1.8m
            _apply_trooper_texture(model_root)

        SkinType.MILITARY_TACTICAL_OPERATOR:
            model_root = MILITARY_TACTICAL_SCENE.instantiate() as Node3D

        SkinType.SOCOM_OPERATOR:
            model_root = OPERATOR_SCENE.instantiate() as Node3D

        SkinType.MIXAMO_MANNEQUIN:
            model_root = MIXAMO_SKIN_SCENE.instantiate() as Node3D

        SkinType.PS1_NIGHT_VISION_SEAL:
            model_root = PS1_NV_SCENE.instantiate() as Node3D
    
    model_root.name = "PreviewOperator"
    model_root.rotation.y = PI
    add_child(model_root)

    if skin == SkinType.SOCOM_OPERATOR:
        _hide_baked_rifle_parts(model_root)

    animation_player = _find_animation_player(model_root)
    skeleton = _find_skeleton(model_root)

    # If model has a skeleton but no AnimationPlayer (e.g. trooper_rigged.fbx),
    # create one so we can load and play Mixamo clips dynamically
    if animation_player == null and skeleton != null:
        animation_player = AnimationPlayer.new()
        animation_player.name = "AnimationPlayer"
        skeleton.add_child(animation_player)
        animation_player.owner = model_root
        # Point the animation player root at the skeleton so bone tracks resolve
        animation_player.root_node = animation_player.get_path_to(skeleton)

    if animation_player:
        dynamic_anim_lib = AnimationLibrary.new()
        if not animation_player.has_animation_library("dyn"):
            animation_player.add_animation_library("dyn", dynamic_anim_lib)

    _rebuild_weapon_socket()
    _rebuild_limb_bubbles()

    baked_clips.clear()
    if animation_player:
        for anim_name in animation_player.get_animation_list():
            if not str(anim_name).begins_with("dyn/"):
                baked_clips.append(StringName(anim_name))
        baked_clips.sort()

    all_clip_entries = workshop_repository.build_entries(
        baked_clips,
        fbx_files,
        authored_animation_files
    )

    if not highlight_shortlist_loaded:
        _load_highlighted_shortlist()
        highlight_shortlist_loaded = true

    _filter_category(current_category)
    clip_index = 0
    if active_editor_page == "Build":
        _show_body_composer_rest_pose()
    else:
        _play_selected()
    _refresh_clip_list_ui()

func _hide_mannequin_mesh(node: Node) -> void:
    if node is MeshInstance3D:
        node.visible = false
    for c in node.get_children():
        _hide_mannequin_mesh(c)

func _apply_trooper_texture(node: Node) -> void:
    if node is MeshInstance3D:
        var mat := StandardMaterial3D.new()
        mat.albedo_texture = PS1_GAS_MASK_TEX
        mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
        mat.roughness = 0.9
        (node as MeshInstance3D).material_override = mat
    for c in node.get_children():
        _apply_trooper_texture(c)

func _generate_auto_skinned_mesh(src_mesh: ArrayMesh, skel: Skeleton3D) -> ArrayMesh:
    var src_arrays := src_mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = src_arrays[Mesh.ARRAY_VERTEX]
    var normals: PackedVector3Array = src_arrays[Mesh.ARRAY_NORMAL]
    var uvs: PackedVector2Array = src_arrays[Mesh.ARRAY_TEX_UV]
    
    var bones: PackedInt32Array = PackedInt32Array()
    var weights: PackedFloat32Array = PackedFloat32Array()
    var new_vertices: PackedVector3Array = PackedVector3Array()
    
    # Scale from 3.34m to 1.85m standard height
    var scale_factor := 1.85 / 3.344682
    
    var head_idx := skel.find_bone("mixamorig_Head")
    if head_idx == -1: head_idx = skel.find_bone("mixamorig:Head")
    var spine_idx := skel.find_bone("mixamorig_Spine2")
    if spine_idx == -1: spine_idx = skel.find_bone("mixamorig:Spine2")
    var hips_idx := skel.find_bone("mixamorig_Hips")
    if hips_idx == -1: hips_idx = skel.find_bone("mixamorig:Hips")
    var r_arm_idx := skel.find_bone("mixamorig_RightArm")
    if r_arm_idx == -1: r_arm_idx = skel.find_bone("mixamorig:RightArm")
    var r_forearm_idx := skel.find_bone("mixamorig_RightForeArm")
    if r_forearm_idx == -1: r_forearm_idx = skel.find_bone("mixamorig:RightForeArm")
    var l_arm_idx := skel.find_bone("mixamorig_LeftArm")
    if l_arm_idx == -1: l_arm_idx = skel.find_bone("mixamorig:LeftArm")
    var l_forearm_idx := skel.find_bone("mixamorig_LeftForeArm")
    if l_forearm_idx == -1: l_forearm_idx = skel.find_bone("mixamorig:LeftForeArm")
    var r_thigh_idx := skel.find_bone("mixamorig_RightUpLeg")
    if r_thigh_idx == -1: r_thigh_idx = skel.find_bone("mixamorig:RightUpLeg")
    var r_leg_idx := skel.find_bone("mixamorig_RightLeg")
    if r_leg_idx == -1: r_leg_idx = skel.find_bone("mixamorig:RightLeg")
    var r_foot_idx := skel.find_bone("mixamorig_RightFoot")
    if r_foot_idx == -1: r_foot_idx = skel.find_bone("mixamorig:RightFoot")
    var l_thigh_idx := skel.find_bone("mixamorig_LeftUpLeg")
    if l_thigh_idx == -1: l_thigh_idx = skel.find_bone("mixamorig:LeftUpLeg")
    var l_leg_idx := skel.find_bone("mixamorig_LeftLeg")
    if l_leg_idx == -1: l_leg_idx = skel.find_bone("mixamorig:LeftLeg")
    var l_foot_idx := skel.find_bone("mixamorig_LeftFoot")
    if l_foot_idx == -1: l_foot_idx = skel.find_bone("mixamorig:LeftFoot")
    
    for v in vertices:
        var scaled_v := v * scale_factor
        new_vertices.append(scaled_v)
        
        var chosen_bone := hips_idx
        var y := scaled_v.y
        var x := scaled_v.x
        
        if y > 1.48:
            chosen_bone = head_idx
        elif y > 0.95:
            if x > 0.28:
                chosen_bone = r_forearm_idx if y < 1.30 else r_arm_idx
            elif x < -0.28:
                chosen_bone = l_forearm_idx if y < 1.30 else l_arm_idx
            else:
                chosen_bone = spine_idx
        else:
            if x >= 0:
                if y < 0.18: chosen_bone = r_foot_idx
                elif y < 0.55: chosen_bone = r_leg_idx
                else: chosen_bone = r_thigh_idx
            else:
                if y < 0.18: chosen_bone = l_foot_idx
                elif y < 0.55: chosen_bone = l_leg_idx
                else: chosen_bone = l_thigh_idx
                
        bones.append(chosen_bone if chosen_bone != -1 else 0)
        bones.append(0)
        bones.append(0)
        bones.append(0)
        
        weights.append(1.0)
        weights.append(0.0)
        weights.append(0.0)
        weights.append(0.0)
        
    var new_arrays := []
    new_arrays.resize(Mesh.ARRAY_MAX)
    new_arrays[Mesh.ARRAY_VERTEX] = new_vertices
    new_arrays[Mesh.ARRAY_NORMAL] = normals
    new_arrays[Mesh.ARRAY_TEX_UV] = uvs
    new_arrays[Mesh.ARRAY_BONES] = bones
    new_arrays[Mesh.ARRAY_WEIGHTS] = weights
    
    var out_mesh := ArrayMesh.new()
    out_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)
    return out_mesh

func _build_segmented_meshes(src_mesh: ArrayMesh, skel: Skeleton3D, bone_map: Dictionary) -> Dictionary:
    var src_arrays := src_mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = src_arrays[Mesh.ARRAY_VERTEX]
    var normals: PackedVector3Array = src_arrays[Mesh.ARRAY_NORMAL]
    var uvs: PackedVector2Array = src_arrays[Mesh.ARRAY_TEX_UV]
    var indices: PackedInt32Array = src_arrays[Mesh.ARRAY_INDEX]
    
    var seg_verts := {"head": PackedVector3Array(), "torso": PackedVector3Array(), "left_arm": PackedVector3Array(), "right_arm": PackedVector3Array(), "left_leg": PackedVector3Array(), "right_leg": PackedVector3Array()}
    var seg_norms := {"head": PackedVector3Array(), "torso": PackedVector3Array(), "left_arm": PackedVector3Array(), "right_arm": PackedVector3Array(), "left_leg": PackedVector3Array(), "right_leg": PackedVector3Array()}
    var seg_uvs := {"head": PackedVector2Array(), "torso": PackedVector2Array(), "left_arm": PackedVector2Array(), "right_arm": PackedVector2Array(), "left_leg": PackedVector2Array(), "right_leg": PackedVector2Array()}
    
    var scale_factor := 1.85 / 3.344682
    
    for i in range(0, indices.size(), 3):
        var idx0 := indices[i]
        var idx1 := indices[i+1]
        var idx2 := indices[i+2]
        
        var v0 := vertices[idx0] * scale_factor
        var v1 := vertices[idx1] * scale_factor
        var v2 := vertices[idx2] * scale_factor
        var center := (v0 + v1 + v2) / 3.0
        
        var target := "torso"
        if center.y > 1.45:
            target = "head"
        elif center.y > 0.95:
            if center.x > 0.22: target = "right_arm"
            elif center.x < -0.22: target = "left_arm"
            else: target = "torso"
        else:
            if center.x >= 0: target = "right_leg"
            else: target = "left_leg"
            
        var bone_name: String = bone_map.get(target, "mixamorig_Hips")
        var b_idx := skel.find_bone(bone_name)
        var bone_rest: Transform3D = skel.get_bone_global_rest(b_idx) if b_idx != -1 else Transform3D.IDENTITY
        var inv_rest := bone_rest.affine_inverse()
        
        for v_idx in [idx0, idx1, idx2]:
            var world_v := vertices[v_idx] * scale_factor
            var local_v := inv_rest * world_v
            var local_norm := inv_rest.basis * normals[v_idx]
            
            seg_verts[target].append(local_v)
            seg_norms[target].append(local_norm)
            seg_uvs[target].append(uvs[v_idx])
            
    var result := {}
    for key in seg_verts.keys():
        if seg_verts[key].size() > 0:
            var arrs := []
            arrs.resize(Mesh.ARRAY_MAX)
            arrs[Mesh.ARRAY_VERTEX] = seg_verts[key]
            arrs[Mesh.ARRAY_NORMAL] = seg_norms[key]
            arrs[Mesh.ARRAY_TEX_UV] = seg_uvs[key]
            var m := ArrayMesh.new()
            m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
            result[key] = m
    return result
