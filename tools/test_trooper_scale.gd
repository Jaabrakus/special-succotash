extends SceneTree

func _init():
    var p := load("res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx") as PackedScene
    var inst := p.instantiate()
    var skel: Skeleton3D = _find_skel(inst)
    var mi: MeshInstance3D = _find_mesh(inst)
    
    print("=== RIGGED TROOPER SCALE/POSITION CHECK ===")
    print("Root transform: ", inst.transform)
    if skel:
        print("Skeleton transform: ", skel.transform)
        var hips_idx := skel.find_bone("mixamorig_Hips")
        if hips_idx != -1:
            var hips_rest := skel.get_bone_global_rest(hips_idx)
            print("Hips global rest origin: ", hips_rest.origin)
        var head_idx := skel.find_bone("mixamorig_Head")
        if head_idx != -1:
            var head_rest := skel.get_bone_global_rest(head_idx)
            print("Head global rest origin: ", head_rest.origin)
        var foot_idx := skel.find_bone("mixamorig_RightFoot")
        if foot_idx != -1:
            var foot_rest := skel.get_bone_global_rest(foot_idx)
            print("RightFoot global rest origin: ", foot_rest.origin)
    if mi:
        print("Mesh AABB: ", mi.get_aabb())
        print("Mesh transform: ", mi.transform)
    quit()

func _find_skel(n: Node) -> Skeleton3D:
    if n is Skeleton3D: return n
    for c in n.get_children():
        var found := _find_skel(c)
        if found: return found
    return null

func _find_mesh(n: Node) -> MeshInstance3D:
    if n is MeshInstance3D: return n
    for c in n.get_children():
        var found := _find_mesh(c)
        if found: return found
    return null
