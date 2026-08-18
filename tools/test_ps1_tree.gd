extends SceneTree

func _init():
    var nv_path := "res://assets/characters/ps1_night_vision_operator/NVoperatorsoldier.glb"
    var p := load(nv_path) as PackedScene
    if p:
        var inst := p.instantiate()
        var skel: Skeleton3D = inst.find_child("Skeleton3D", true, false)
        if skel:
            print("=== PS1 SKELETON BONES (", skel.get_bone_count(), ") ===")
            for i in range(skel.get_bone_count()):
                var parent_idx := skel.get_bone_parent(i)
                var parent_name := skel.get_bone_name(parent_idx) if parent_idx != -1 else "ROOT"
                print("Bone ", i, ": '", skel.get_bone_name(i), "' (Parent: ", parent_name, ")")
    quit()
