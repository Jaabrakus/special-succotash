extends SceneTree

func _init():
    var obj_mesh := load("res://assets/characters/ps1_gas_mask_soldier/sasman5.obj") as ArrayMesh
    var mix_scene := load("res://assets/characters/operator3d/mixamo_beta_skin.glb") as PackedScene
    var mix_inst := mix_scene.instantiate()
    var skel: Skeleton3D = _find_skel(mix_inst)
    
    var bone_map := {
        "head": "mixamorig_Head",
        "torso": "mixamorig_Spine1",
        "left_arm": "mixamorig_LeftArm",
        "right_arm": "mixamorig_RightArm",
        "left_leg": "mixamorig_LeftUpLeg",
        "right_leg": "mixamorig_RightUpLeg"
    }
    
    var segments := _build_segmented_meshes(obj_mesh, skel, bone_map)
    print("=== SEGMENTED PS1 RIG REST TRANSFORMS VERIFIED ===")
    for k in segments.keys():
        print("  Segment ", k, " built with ", segments[k].get_surface_count(), " surfaces")
    quit()

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
            
        var bone_name: String = bone_map[target]
        var b_idx := skel.find_bone(bone_name)
        var bone_rest: Transform3D = skel.get_bone_global_rest(b_idx)
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

func _find_skel(n: Node) -> Skeleton3D:
    if n is Skeleton3D: return n
    for c in n.get_children():
        var found := _find_skel(c)
        if found: return found
    return null
