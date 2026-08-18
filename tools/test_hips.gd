extends SceneTree

func _init():
    var scenes := [
        "res://assets/characters/operator3d/socom_141_operator_animated.glb",
        "res://assets/characters/operator3d/mixamo_beta_skin.glb",
        "res://assets/characters/ps1_night_vision_operator/NVoperatorsoldier.glb"
    ]
    for s_path in scenes:
        print("\n--- HIPS REST CHECK: ", s_path)
        var p := load(s_path) as PackedScene
        if p:
            var inst := p.instantiate()
            var skel: Skeleton3D = _find_skel(inst)
            if skel:
                var hips_idx := skel.find_bone("mixamorig_Hips")
                if hips_idx == -1: hips_idx = skel.find_bone("Spinelower")
                if hips_idx != -1:
                    print("Hips Bone: '", skel.get_bone_name(hips_idx), "' Rest Pose Pos: ", skel.get_bone_rest(hips_idx).origin)
    quit()

func _find_skel(n: Node) -> Skeleton3D:
    if n is Skeleton3D: return n
    for c in n.get_children():
        var found := _find_skel(c)
        if found: return found
    return null
