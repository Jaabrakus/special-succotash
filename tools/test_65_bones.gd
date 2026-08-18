extends SceneTree

func _init():
    var op_scene := load("res://assets/characters/operator3d/socom_141_operator_animated.glb") as PackedScene
    var op_inst := op_scene.instantiate()
    var skel: Skeleton3D = _find_skel(op_inst)
    
    var sample_anims := [
        "res://assets/animations/mixamo/Lite Rifle Pack/run forward.fbx",
        "res://assets/animations/mixamo/Basic Shooter Pack/Shooter Pack/Rifle Firing.fbx",
        "res://assets/animations/mixamo/Basic Shooter Pack/Shooter Pack/Rifle Reloading.fbx",
        "res://assets/animations/mixamo/Running Dive Roll.fbx"
    ]
    
    for fbx_path in sample_anims:
        if not ResourceLoader.exists(fbx_path):
            continue
        var p_fbx := load(fbx_path) as PackedScene
        var fbx_inst := p_fbx.instantiate()
        var ap_fbx: AnimationPlayer = fbx_inst.find_child("AnimationPlayer", true, false)
        var src_anim: Animation = ap_fbx.get_animation(ap_fbx.get_animation_list()[0])
        
        print("\n--- Testing: ", fbx_path.get_file(), " (Tracks: ", src_anim.get_track_count(), ") ---")
        var matched := 0
        var finger_matches := 0
        for i in range(src_anim.get_track_count()):
            var old_path_str := str(src_anim.track_get_path(i))
            var raw_bone := old_path_str.split(":")[-1].replace("mixamorig:", "mixamorig_")
            if not raw_bone.begins_with("mixamorig_"):
                raw_bone = "mixamorig_" + raw_bone
                
            var b_idx := skel.find_bone(raw_bone)
            if b_idx != -1:
                matched += 1
                if "Hand" in raw_bone or "Thumb" in raw_bone or "Index" in raw_bone or "Pinky" in raw_bone or "Ring" in raw_bone or "Middle" in raw_bone:
                    finger_matches += 1
            else:
                print("  Unmatched: ", raw_bone)
        print("MATCHED: ", matched, " / ", src_anim.get_track_count(), " (Finger/Hand joints matched: ", finger_matches, ")")
    quit()

func _find_skel(n: Node) -> Skeleton3D:
    if n is Skeleton3D: return n
    for c in n.get_children():
        var found := _find_skel(c)
        if found: return found
    return null
