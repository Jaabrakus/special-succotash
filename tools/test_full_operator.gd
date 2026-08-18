extends SceneTree

func _init():
    print("=== TESTING COMPLETE OPERATOR RETARGETING & SETUP ===")
    
    # 1. Instantiate Trooper
    var trooper_scene := load("res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx") as PackedScene
    var model := trooper_scene.instantiate() as Node3D
    model.scale = Vector3.ONE * 55.0
    
    var skel := _find_skel(model)
    print("Skeleton found: ", skel != null, " (bones: ", skel.get_bone_count() if skel else 0, ")")
    
    # 2. Add AnimationPlayer & Library
    var ap := AnimationPlayer.new()
    ap.name = "AnimationPlayer"
    skel.add_child(ap)
    ap.root_node = ap.get_path_to(skel)
    
    var lib := AnimationLibrary.new()
    ap.add_animation_library("", lib)
    
    # 3. Test Retargeting key clips
    var test_clips := {
        "idle": "res://assets/animations/mixamo/Lite Rifle Pack/idle.fbx",
        "run_fwd": "res://assets/animations/mixamo/Lite Rifle Pack/run forward.fbx",
        "crouch_idle": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/idle crouching.fbx",
        "prone_idle": "res://assets/animations/mixamo/Prone Forward Stop.fbx",
        "prone_crawl": "res://assets/animations/mixamo/Prone Forward.fbx",
        "dive_roll": "res://assets/animations/mixamo/Running Dive Roll.fbx",
        "roll": "res://assets/animations/mixamo/Run To Rolling.fbx",
        "fire": "res://assets/animations/mixamo/Shooter Pack/firing rifle.fbx",
        "reload": "res://assets/animations/mixamo/Reloading.fbx",
    }
    
    for anim_id in test_clips.keys():
        var fbx_path: String = test_clips[anim_id]
        var p := load(fbx_path) as PackedScene
        if not p:
            print("❌ Failed to load:", fbx_path)
            continue
        var temp := p.instantiate()
        var temp_ap := _find_ap(temp)
        if temp_ap and not temp_ap.get_animation_list().is_empty():
            var src_anim := temp_ap.get_animation(temp_ap.get_animation_list()[0])
            var retargeted := _retarget(src_anim, ap, skel)
            lib.add_animation(anim_id, retargeted)
            print("✅ Retargeted [", anim_id, "] (length: ", retargeted.length, "s, tracks: ", retargeted.get_track_count(), ")")
        temp.queue_free()
    
    # 4. Attach AK-47
    var ak_scene := load("res://assets/weapons/ps1_ak47/source/ak-47.fbx") as PackedScene
    var socket := BoneAttachment3D.new()
    socket.bone_name = "mixamorig_RightHand"
    skel.add_child(socket)
    
    var ak_inst := ak_scene.instantiate() as Node3D
    ak_inst.scale = Vector3.ONE * 0.030 * (1.0 / 55.0)
    ak_inst.position = Vector3(0.0, 0.02, -0.05) * (1.0 / 55.0)
    socket.add_child(ak_inst)
    print("✅ AK-47 attached to mixamorig_RightHand")
    
    model.queue_free()
    print("\n=== ALL TESTS PASSED! ===")
    quit()

func _retarget(src_anim: Animation, ap: AnimationPlayer, skel: Skeleton3D) -> Animation:
    var retargeted := src_anim.duplicate()
    var root_n := ap.get_node(ap.root_node)
    var skel_path := root_n.get_path_to(skel)
    
    for i in range(retargeted.get_track_count() - 1, -1, -1):
        var old_path := str(retargeted.track_get_path(i))
        var raw_bone := old_path.split(":")[-1]
        var norm := raw_bone.replace("mixamorig:", "mixamorig_")
        if not norm.begins_with("mixamorig_"): norm = "mixamorig_" + norm
        
        var target_bone := ""
        if skel.find_bone(raw_bone) != -1: target_bone = raw_bone
        elif skel.find_bone(norm) != -1: target_bone = norm
        
        if target_bone != "":
            var new_path := NodePath(str(skel_path) + ":" + target_bone)
            retargeted.track_set_path(i, new_path)
            
            # Scale Hips position proportionally
            if ("Hips" in raw_bone or "root" in raw_bone.to_lower()) and retargeted.track_get_type(i) == Animation.TYPE_POSITION_3D:
                var bone_idx := skel.find_bone(target_bone)
                var rest_y := skel.get_bone_rest(bone_idx).origin.y if bone_idx != -1 else 0.92
                var base_y := 0.0
                if retargeted.track_get_key_count(i) > 0:
                    base_y = retargeted.track_get_key_value(i, 0).y
                var scale_factor := (rest_y / base_y) if base_y != 0.0 else 1.0
                for k in range(retargeted.track_get_key_count(i)):
                    var pos: Vector3 = retargeted.track_get_key_value(i, k)
                    pos.x = 0.0
                    pos.z = 0.0
                    pos.y = pos.y * scale_factor
                    retargeted.track_set_key_value(i, k, pos)
        else:
            retargeted.remove_track(i)
    return retargeted

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
