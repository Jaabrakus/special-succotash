extends SceneTree

func _init():
    var fbx_path := "res://assets/animations/mixamo/Lite Rifle Pack/run forward.fbx"
    var p_fbx := load(fbx_path) as PackedScene
    var fbx_inst := p_fbx.instantiate()
    var ap_fbx: AnimationPlayer = fbx_inst.find_child("AnimationPlayer", true, false)
    var src_anim: Animation = ap_fbx.get_animation(ap_fbx.get_animation_list()[0])
    
    var op_scene := load("res://assets/characters/operator3d/socom_141_operator_animated.glb") as PackedScene
    var op_inst := op_scene.instantiate()
    var op_skel: Skeleton3D = _find_skel(op_inst)
    
    print("Source FBX tracks: ", src_anim.get_track_count())
    var matched := 0
    for i in range(src_anim.get_track_count()):
        var old_path_str := str(src_anim.track_get_path(i))
        var raw_bone := old_path_str.split(":")[-1] # e.g. mixamorig_Hips
        # Normalize
        var clean_bone := raw_bone.replace("mixamorig:", "mixamorig_")
        if not clean_bone.begins_with("mixamorig_") and op_skel.find_bone("mixamorig_" + clean_bone) != -1:
            clean_bone = "mixamorig_" + clean_bone
            
        var bone_idx := op_skel.find_bone(clean_bone)
        if bone_idx != -1:
            matched += 1
            if matched <= 5:
                print("  Matched track '", raw_bone, "' -> Skeleton bone '", op_skel.get_bone_name(bone_idx), "' (idx ", bone_idx, ")")
        else:
            print("  UNMATCHED: '", raw_bone, "'")
            
    print("TOTAL MATCHED: ", matched, " / ", src_anim.get_track_count())
    quit()

func _find_skel(n: Node) -> Skeleton3D:
    if n is Skeleton3D: return n
    for c in n.get_children():
        var found := _find_skel(c)
        if found: return found
    return null
