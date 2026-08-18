extends SceneTree

func _init():
    var p := load("res://assets/weapons/ps1_ak47/source/ak-47.fbx") as PackedScene
    var inst := p.instantiate()
    print("AK-47 Root:", inst.name)
    _inspect_nodes(inst, 0)
    inst.queue_free()
    quit()

func _inspect_nodes(n: Node, depth: int):
    var indent := "  ".repeat(depth)
    print(indent, "- ", n.name, " (", n.get_class(), ")")
    if n is Node3D:
        print(indent, "  Pos: ", n.position, " Rot: ", n.rotation_degrees, " Scale: ", n.scale)
    if n is MeshInstance3D:
        print(indent, "  Mesh AABB: ", n.get_aabb())
    for c in n.get_children():
        _inspect_nodes(c, depth + 1)
