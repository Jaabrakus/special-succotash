extends SceneTree

# Full audit of every skin/scene used by operator_animation_lab.gd

func _init():
    print("=" .repeat(70))
    print("  ANIMATION LAB ASSET AUDIT")
    print("=" .repeat(70))
    
    _audit("PS1_GAS_MASK_RIGGED", "res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx")
    _audit("MILITARY_TACTICAL",   "res://assets/characters/military_tactical_operator/Anim_Idle_MIL_R5.fbx")
    _audit("SOCOM_OPERATOR",      "res://assets/characters/operator3d/socom_141_operator_animated.glb")
    _audit("MIXAMO_MANNEQUIN",    "res://assets/characters/operator3d/mixamo_beta_skin.glb")
    _audit("PS1_NV_SEAL",         "res://assets/characters/ps1_night_vision_operator/NVoperatorsoldier.glb")
    
    print("\n--- TEXTURE CHECK ---")
    var tex := load("res://assets/characters/ps1_gas_mask_soldier/trooper.png")
    print("  trooper.png: ", "OK" if tex else "MISSING")
    var tex2 := load("res://assets/characters/ps1_gas_mask_soldier/trooper_rigged_0.png")
    print("  trooper_rigged_0.png: ", "OK" if tex2 else "MISSING")
    
    print("\n" + "=" .repeat(70))
    quit()

func _audit(label: String, path: String) -> void:
    print("\n--- ", label, " ---")
    print("  Path: ", path)
    
    var res := load(path)
    if res == null:
        print("  STATUS: ❌ FAILED TO LOAD")
        return
    
    if not (res is PackedScene):
        print("  STATUS: ❌ NOT A PackedScene (is ", res.get_class(), ")")
        return
    
    var scene: PackedScene = res as PackedScene
    var inst := scene.instantiate()
    if inst == null:
        print("  STATUS: ❌ FAILED TO INSTANTIATE")
        return
    
    print("  Root Node: ", inst.name, " (", inst.get_class(), ")")
    
    var skel := _find_skel(inst)
    var anim_player := _find_anim_player(inst)
    var mesh_count := _count_meshes(inst)
    var visible_mesh_count := _count_visible_meshes(inst)
    
    print("  Skeleton: ", ("✅ " + str(skel.get_bone_count()) + " bones") if skel else "❌ NONE")
    print("  AnimPlayer: ", ("✅ " + str(anim_player.get_animation_list().size()) + " clips") if anim_player else "⚠️ NONE")
    print("  MeshInstance3D count: ", mesh_count)
    print("  Visible meshes: ", visible_mesh_count)
    
    if skel:
        # Check key bones
        var key_bones := ["mixamorig_Hips", "mixamorig_RightHand", "mixamorig_Head", "mixamorig_LeftFoot"]
        var found := 0
        for b in key_bones:
            if skel.find_bone(b) != -1:
                found += 1
        print("  Key Mixamo bones found: ", found, "/", key_bones.size())
    
    if visible_mesh_count == 0:
        print("  STATUS: ⚠️ NO VISIBLE MESH — character will be INVISIBLE")
    elif skel == null:
        print("  STATUS: ⚠️ NO SKELETON — animations won't work")
    else:
        print("  STATUS: ✅ READY")
    
    inst.queue_free()

func _find_skel(n: Node) -> Skeleton3D:
    if n is Skeleton3D: return n
    for c in n.get_children():
        var found := _find_skel(c)
        if found: return found
    return null

func _find_anim_player(n: Node) -> AnimationPlayer:
    if n is AnimationPlayer: return n
    for c in n.get_children():
        var found := _find_anim_player(c)
        if found: return found
    return null

func _count_meshes(n: Node) -> int:
    var count := 0
    if n is MeshInstance3D: count += 1
    for c in n.get_children():
        count += _count_meshes(c)
    return count

func _count_visible_meshes(n: Node) -> int:
    var count := 0
    if n is MeshInstance3D and n.visible:
        count += 1
    for c in n.get_children():
        count += _count_visible_meshes(c)
    return count
