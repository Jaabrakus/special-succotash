extends SceneTree

func _init():
    var files := [
        "res://assets/animations/mixamo/Prone Forward Stop.fbx",
        "res://assets/animations/mixamo/Prone Forward.fbx",
        "res://assets/animations/mixamo/Prone Backwards Stop.fbx",
        "res://assets/animations/mixamo/Prone Firing Rifle.fbx",
        "res://assets/animations/mixamo/Prone Reloading.fbx",
    ]
    for p in files:
        var packed := load(p) as PackedScene
        if packed:
            var inst := packed.instantiate()
            var ap := _find_ap(inst)
            var anim := ap.get_animation(ap.get_animation_list()[0])
            for i in range(anim.get_track_count()):
                var path := str(anim.track_get_path(i))
                if "Hips" in path and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
                    print(p.get_file(), " -> Hips Y: ", anim.track_get_key_value(i, 0).y, "m")
            inst.queue_free()
    quit()

func _find_ap(n: Node) -> AnimationPlayer:
    if n is AnimationPlayer: return n
    for c in n.get_children():
        var r := _find_ap(c)
        if r: return r
    return null
