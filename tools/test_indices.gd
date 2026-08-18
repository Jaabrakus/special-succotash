extends SceneTree

func _init():
    var obj_mesh := load("res://assets/characters/ps1_gas_mask_soldier/sasman5.obj") as ArrayMesh
    var src_arrays := obj_mesh.surface_get_arrays(0)
    var indices: PackedInt32Array = src_arrays[Mesh.ARRAY_INDEX]
    print("Has indices: ", indices.size() > 0, " (count: ", indices.size(), ")")
    quit()
