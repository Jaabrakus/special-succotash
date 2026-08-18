extends SceneTree

func _init():
    var op_scene := load("res://assets/characters/operator3d/socom_141_operator_animated.glb") as PackedScene
    var op_inst := op_scene.instantiate()
    var skel: Skeleton3D = _find_skel(op_inst)
    
    print("\nSOCOM OPERATOR Skeleton Bone Global Rest Positions:")
    for i in range(skel.get_bone_count()):
        var b_name := skel.get_bone_name(i)
        if "Hips" in b_name or "Spine" in b_name or "Head" in b_name or "Arm" in b_name or "Leg" in b_name or "Foot" in b_name:
            var global_pos := skel.get_bone_global_rest(i).origin
            print("  Bone ", i, " [", b_name, "] Pos: ", global_pos)
    quit()

func _find_skel(n: Node) -> Skeleton3D:
    if n is Skeleton3D: return n
    for c in n.get_children():
        var found := _find_skel(c)
        if found: return found
    return null
