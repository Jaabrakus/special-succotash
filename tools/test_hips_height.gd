extends SceneTree

func _init():
    var standing_fbx := load("res://assets/animations/mixamo/Lite Rifle Pack/idle.fbx") as PackedScene
    var crouch_fbx := load("res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/idle crouching.fbx") as PackedScene
    var prone_fbx := load("res://assets/animations/mixamo/Prone Forward Stop.fbx") as PackedScene
    
    var stand_ap := _find_ap(standing_fbx.instantiate())
    var crouch_ap := _find_ap(crouch_fbx.instantiate())
    var prone_ap := _find_ap(prone_fbx.instantiate())
    
    var stand_anim := stand_ap.get_animation(stand_ap.get_animation_list()[0])
    var crouch_anim := crouch_ap.get_animation(crouch_ap.get_animation_list()[0])
    var prone_anim := prone_ap.get_animation(prone_ap.get_animation_list()[0])
    
    var stand_y := _get_hips_y(stand_anim)
    var crouch_y := _get_hips_y(crouch_anim)
    var prone_y := _get_hips_y(prone_anim)
    
    print("Source Mixamo Hips Y:")
    print("  Standing:", stand_y, "m")
    print("  Crouch:  ", crouch_y, "m")
    print("  Prone:   ", prone_y, "m")
    
    var conversion_factor := 0.018744 / stand_y # scale to match trooper rest height
    print("\nTrooper In-Game World Hips Y (after 55x scale):")
    print("  Standing:", (stand_y * conversion_factor) * 55.0, "m")
    print("  Crouch:  ", (crouch_y * conversion_factor) * 55.0, "m")
    print("  Prone:   ", (prone_y * conversion_factor) * 55.0, "m")
    
    quit()

func _get_hips_y(anim: Animation) -> float:
    for i in range(anim.get_track_count()):
        var path := str(anim.track_get_path(i))
        if "Hips" in path and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
            if anim.track_get_key_count(i) > 0:
                return anim.track_get_key_value(i, 0).y
    return 0.0

func _find_ap(n: Node) -> AnimationPlayer:
    if n is AnimationPlayer: return n
    for c in n.get_children():
        var r := _find_ap(c)
        if r: return r
    return null
