extends SceneTree

func _init():
    var obj_mesh := load("res://assets/characters/ps1_gas_mask_soldier/sasman5.obj") as ArrayMesh
    var op_scene := load("res://assets/characters/operator3d/socom_141_operator_animated.glb") as PackedScene
    var op_inst := op_scene.instantiate()
    var skel: Skeleton3D = _find_skel(op_inst)
    
    var skinned_mesh := _generate_auto_skinned_mesh(obj_mesh, skel)
    print("Auto-Skinned Mesh Generated Successfully!")
    print("Surface count: ", skinned_mesh.get_surface_count())
    var arrs := skinned_mesh.surface_get_arrays(0)
    print("Vertex count: ", arrs[Mesh.ARRAY_VERTEX].size())
    print("Bones array count: ", arrs[Mesh.ARRAY_BONES].size())
    print("Weights array count: ", arrs[Mesh.ARRAY_WEIGHTS].size())
    quit()

func _generate_auto_skinned_mesh(src_mesh: ArrayMesh, skel: Skeleton3D) -> ArrayMesh:
    var src_arrays := src_mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = src_arrays[Mesh.ARRAY_VERTEX]
    var normals: PackedVector3Array = src_arrays[Mesh.ARRAY_NORMAL]
    var uvs: PackedVector2Array = src_arrays[Mesh.ARRAY_TEX_UV]
    
    var bones: PackedInt32Array = PackedInt32Array()
    var weights: PackedFloat32Array = PackedFloat32Array()
    var new_vertices: PackedVector3Array = PackedVector3Array()
    
    # Scale from 3.34m to 1.85m
    var scale_factor := 1.85 / 3.344682
    
    var head_idx := skel.find_bone("mixamorig_Head")
    var spine_idx := skel.find_bone("mixamorig_Spine2")
    var hips_idx := skel.find_bone("mixamorig_Hips")
    var r_arm_idx := skel.find_bone("mixamorig_RightArm")
    var r_forearm_idx := skel.find_bone("mixamorig_RightForeArm")
    var l_arm_idx := skel.find_bone("mixamorig_LeftArm")
    var l_forearm_idx := skel.find_bone("mixamorig_LeftForeArm")
    var r_thigh_idx := skel.find_bone("mixamorig_RightUpLeg")
    var r_leg_idx := skel.find_bone("mixamorig_RightLeg")
    var r_foot_idx := skel.find_bone("mixamorig_RightFoot")
    var l_thigh_idx := skel.find_bone("mixamorig_LeftUpLeg")
    var l_leg_idx := skel.find_bone("mixamorig_LeftLeg")
    var l_foot_idx := skel.find_bone("mixamorig_LeftFoot")
    
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
                
        # 4 bone weights per vertex in Godot
        bones.append(chosen_bone)
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

func _find_skel(n: Node) -> Skeleton3D:
    if n is Skeleton3D: return n
    for c in n.get_children():
        var found := _find_skel(c)
        if found: return found
    return null
