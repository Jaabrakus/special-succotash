extends SceneTree

func _init():
    var op_scene := load("res://assets/characters/operator3d/socom_141_operator_animated.glb") as PackedScene
    var op_inst := op_scene.instantiate()
    var skel: Skeleton3D = _find_skel(op_inst)
    if skel:
        print("=== ALL BONES IN SOCOM OPERATOR SKELETON ===")
        for i in range(skel.get_bone_count()):
            print("Bone ", i, ": '", skel.get_bone_name(i), "'")
    quit()

func _find_skel(n: Node) -> Skeleton3D:
    if n is Skeleton3D: return n
    for c in n.get_children():
        var found := _find_skel(c)
        if found: return found
    return null
