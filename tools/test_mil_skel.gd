extends SceneTree

func _init():
    var mil_path := "res://assets/characters/military_tactical_operator/Anim_Idle_MIL_R5.fbx"
    var p := load(mil_path) as PackedScene
    if p:
        var inst := p.instantiate()
        var skel: Skeleton3D = _find_skel(inst)
        if skel:
            print("=== MILITARY TACTICAL OPERATOR SKELETON (", skel.get_bone_count(), " bones) ===")
            for i in range(skel.get_bone_count()):
                print("Bone ", i, ": '", skel.get_bone_name(i), "'")
    quit()

func _find_skel(n: Node) -> Skeleton3D:
    if n is Skeleton3D: return n
    for c in n.get_children():
        var found := _find_skel(c)
        if found: return found
    return null
