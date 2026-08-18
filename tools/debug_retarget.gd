extends SceneTree

func _init():
    var p := load("res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx") as PackedScene
    var model_root := p.instantiate()
    var skeleton := _find_skel(model_root)
    
    # Create AP like lab does
    var ap := AnimationPlayer.new()
    ap.name = "AnimationPlayer"
    skeleton.add_child(ap)
    ap.owner = model_root
    ap.root_node = ap.get_path_to(skeleton)
    
    # Create dynamic lib
    var lib := AnimationLibrary.new()
    ap.add_animation_library("dyn", lib)
    
    # Load a real FBX
    var fbx := load("res://assets/animations/mixamo/Lite Rifle Pack/idle.fbx") as PackedScene
    if not fbx:
        print("FAILED: Could not load idle.fbx")
        quit()
        return
    
    var temp := fbx.instantiate()
    var temp_ap := _find_ap(temp)
    var src := temp_ap.get_animation(temp_ap.get_animation_list()[0])
    
    print("=== SOURCE TRACKS ===")
    print("Total: ", src.get_track_count())
    
    # Retarget
    var retargeted := src.duplicate()
    var root_n := ap.get_node(ap.root_node)
    var skel_path := root_n.get_path_to(skeleton)
    
    var matched := 0
    var unmatched := 0
    for i in range(retargeted.get_track_count() - 1, -1, -1):
        var old_path := str(retargeted.track_get_path(i))
        var raw_bone := old_path.split(":")[-1]
        var normalized := raw_bone.replace("mixamorig:", "mixamorig_")
        if not normalized.begins_with("mixamorig_"):
            normalized = "mixamorig_" + normalized
        
        var target_bone := ""
        if skeleton.find_bone(raw_bone) != -1:
            target_bone = raw_bone
        elif skeleton.find_bone(normalized) != -1:
            target_bone = normalized
        
        if target_bone != "":
            var new_path := NodePath(str(skel_path) + ":" + target_bone)
            retargeted.track_set_path(i, new_path)
            matched += 1
        else:
            unmatched += 1
            print("  UNMATCHED: raw=", raw_bone, " norm=", normalized)
            retargeted.remove_track(i)
    
    print("\nMatched: ", matched, " / Unmatched: ", unmatched)
    
    lib.add_animation("idle", retargeted)
    
    # Verify playback
    print("\nHas animation dyn/idle: ", ap.has_animation("dyn/idle"))
    print("Track count in retargeted: ", retargeted.get_track_count())
    print("\nSample track paths:")
    for i in range(min(5, retargeted.get_track_count())):
        print("  ", retargeted.track_get_path(i))
    
    temp.queue_free()
    model_root.queue_free()
    quit()

func _find_skel(n: Node) -> Skeleton3D:
    if n is Skeleton3D: return n
    for c in n.get_children():
        var r := _find_skel(c)
        if r: return r
    return null

func _find_ap(n: Node) -> AnimationPlayer:
    if n is AnimationPlayer: return n
    for c in n.get_children():
        var r := _find_ap(c)
        if r: return r
    return null
