extends SceneTree

func _init():
    var p := load("res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx") as PackedScene
    var inst := p.instantiate()
    var skel: Skeleton3D = _find_skel(inst)
    print("=== RIGGED GAS MASK TROOPER BONES (", skel.get_bone_count(), ") ===")
    for i in range(skel.get_bone_count()):
        print("Bone ", i, ": '", skel.get_bone_name(i), "'")
    quit()

func _find_skel(n: Node) -> Skeleton3D:
    if n is Skeleton3D: return n
    for c in n.get_children():
        var found := _find_skel(c)
        if found: return found
    return null
