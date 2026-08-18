extends SceneTree

func _init():
    var p := load("res://assets/weapons/ps1_ak47/source/ak-47.fbx") as PackedScene
    var inst := p.instantiate()
    
    # Calculate the bounding box of the whole assembly
    var min_pt := Vector3(INF, INF, INF)
    var max_pt := Vector3(-INF, -INF, -INF)
    
    for c in inst.get_children():
        if c is MeshInstance3D:
            var aabb: AABB = c.get_aabb()
            var t: Transform3D = c.transform
            for corner_idx in range(8):
                var local_corner := aabb.position + Vector3(
                    aabb.size.x if (corner_idx & 1) else 0.0,
                    aabb.size.y if (corner_idx & 2) else 0.0,
                    aabb.size.z if (corner_idx & 4) else 0.0
                )
                var world_corner := t * local_corner
                min_pt.x = minf(min_pt.x, world_corner.x)
                min_pt.y = minf(min_pt.y, world_corner.y)
                min_pt.z = minf(min_pt.z, world_corner.z)
                max_pt.x = maxf(max_pt.x, world_corner.x)
                max_pt.y = maxf(max_pt.y, world_corner.y)
                max_pt.z = maxf(max_pt.z, world_corner.z)
                
    print("AK-47 Assembly Bounds:")
    print("  Min:", min_pt)
    print("  Max:", max_pt)
    print("  Size:", max_pt - min_pt)
    print("  Center:", (min_pt + max_pt) * 0.5)
    
    # Notice Trigger position: (0.0, 1.058, 4.097)
    # The pistol grip is right behind and below the trigger!
    var grip_pivot := Vector3(0.0, 1.0, 4.0)
    print("  Grip offset to subtract:", grip_pivot)
    
    inst.queue_free()
    quit()
