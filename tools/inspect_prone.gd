extends SceneTree

func _init():
    var prone_fbx := load("res://assets/animations/mixamo/Prone Forward.fbx") as PackedScene
    var inst := prone_fbx.instantiate()
    var ap := _find_ap(inst)
    var anim := ap.get_animation(ap.get_animation_list()[0])
    
    print("=== PRONE FORWARD TRACKS ===")
    for i in range(anim.get_track_count()):
        var path := str(anim.track_get_path(i))
        if "Hips" in path or "Spine" in path:
            print("Track[", i, "] Path: ", path, " Type: ", anim.track_get_type(i))
            if anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
                print("  Key 0 Pos: ", anim.track_get_key_value(i, 0))
            if anim.track_get_type(i) == Animation.TYPE_ROTATION_3D:
                print("  Key 0 Rot: ", anim.track_get_key_value(i, 0).get_euler())
    quit()

func _find_ap(n: Node) -> AnimationPlayer:
    if n is AnimationPlayer: return n
    for c in n.get_children():
        var r := _find_ap(c)
        if r: return r
    return null
