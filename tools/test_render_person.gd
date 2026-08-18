extends SceneTree

func _init():
    var nv_scene := load("res://assets/characters/ps1_night_vision_operator/NVoperatorsoldier.glb") as PackedScene
    var inst := nv_scene.instantiate()
    print("NV Operator Instantiated successfully!")
    var skel: Skeleton3D = _find_skel(inst)
    if skel:
        print("Skel found with bones: ", skel.get_bone_count())
    quit()

func _find_skel(n: Node) -> Skeleton3D:
    if n is Skeleton3D: return n
    for c in n.get_children():
        var found := _find_skel(c)
        if found: return found
    return null
