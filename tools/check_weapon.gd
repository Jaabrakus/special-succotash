extends SceneTree

func _init():
    print("=== WEAPON ASSET CHECK ===")
    
    # Check the AK-47 FBX
    var ak := load("res://assets/weapons/ps1_ak47/source/ak-47.fbx")
    if ak:
        print("AK-47 FBX: LOADED (type: ", ak.get_class(), ")")
        if ak is PackedScene:
            var inst := (ak as PackedScene).instantiate()
            print("  Root: ", inst.name, " (", inst.get_class(), ")")
            var mi := _find_mesh(inst)
            if mi:
                print("  Mesh AABB: ", mi.get_aabb())
                print("  Mesh transform: ", mi.transform)
            else:
                print("  NO MeshInstance3D found")
            inst.queue_free()
    else:
        print("AK-47 FBX: FAILED TO LOAD")
    
    # Check what the lab is currently using for weapons
    print("\n=== LAB WEAPON SETUP ===")
    var lab_script := FileAccess.open("res://scripts/labs/operator_animation_lab.gd", FileAccess.READ)
    if lab_script:
        var text := lab_script.get_as_text()
        # Find weapon-related constants
        for line in text.split("\n"):
            if "weapon" in line.to_lower() and ("const" in line.to_lower() or "preload" in line.to_lower() or "var.*weapon" in line.to_lower()):
                print("  ", line.strip_edges())
    
    quit()

func _find_mesh(n: Node) -> MeshInstance3D:
    if n is MeshInstance3D: return n
    for c in n.get_children():
        var r := _find_mesh(c)
        if r: return r
    return null
