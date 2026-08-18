extends SceneTree

func _init():
    var clips := [
        "res://assets/animations/mixamo/Lite Rifle Pack/idle.fbx",
        "res://assets/animations/mixamo/Lite Rifle Pack/run forward.fbx",
        "res://assets/animations/mixamo/Lite Rifle Pack/run backward.fbx",
        "res://assets/animations/mixamo/Lite Rifle Pack/run left.fbx",
        "res://assets/animations/mixamo/Lite Rifle Pack/run right.fbx",
        "res://assets/animations/mixamo/Lite Rifle Pack/run forward left.fbx",
        "res://assets/animations/mixamo/Lite Rifle Pack/run forward right.fbx",
        "res://assets/animations/mixamo/Lite Rifle Pack/run backward left.fbx",
        "res://assets/animations/mixamo/Lite Rifle Pack/run backward right.fbx",
        "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/idle crouching.fbx",
        "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk crouching forward.fbx",
        "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk crouching backward.fbx",
        "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk crouching left.fbx",
        "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/walk crouching right.fbx",
        "res://assets/animations/mixamo/Prone Forward Stop.fbx",
        "res://assets/animations/mixamo/Prone Forward.fbx",
        "res://assets/animations/mixamo/Prone Backwards Stop.fbx",
        "res://assets/animations/mixamo/Prone Firing Rifle.fbx",
        "res://assets/animations/mixamo/Prone Reloading.fbx",
        "res://assets/animations/mixamo/Running Dive Roll.fbx",
        "res://assets/animations/mixamo/Run To Rolling.fbx",
        "res://assets/animations/mixamo/Shooter Pack/rifle aiming idle.fbx",
        "res://assets/animations/mixamo/Shooter Pack/firing rifle.fbx",
        "res://assets/animations/mixamo/Shooter Pack/reloading.fbx",
    ]
    
    print("=== CHECKING CORE MIXAMO CLIPS ===")
    var missing := 0
    for p in clips:
        var res := load(p)
        if res == null:
            print("❌ MISSING:", p)
            missing += 1
        else:
            print("✅ OK:", p.get_file())
    
    print("\nResult: ", clips.size() - missing, "/", clips.size(), " clips found.")
    quit()
