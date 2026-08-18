extends SceneTree

const MIXAMO_TO_PS1_MAP := {
    "mixamorig_Hips": "Spinelower",
    "mixamorig_Spine": "Spinelower",
    "mixamorig_Spine1": "Spineupper",
    "mixamorig_Spine2": "Spineupper",
    "mixamorig_Neck": "Neck",
    "mixamorig_Head": "head",
    "mixamorig_LeftShoulder": "Spineupper",
    "mixamorig_LeftArm": "ArmUpper.L",
    "mixamorig_LeftForeArm": "ArmLower.L",
    "mixamorig_LeftHand": "Hand.L.001",
    "mixamorig_RightShoulder": "Spineupper",
    "mixamorig_RightArm": "ArmUpper.R",
    "mixamorig_RightForeArm": "ArmLower.R",
    "mixamorig_RightHand": "Hand.R.001",
    "mixamorig_LeftUpLeg": "LegThigh.L",
    "mixamorig_LeftLeg": "LegShin.L",
    "mixamorig_LeftFoot": "Foot.L",
    "mixamorig_LeftToeBase": "FootToe.L",
    "mixamorig_RightUpLeg": "LegThigh.R",
    "mixamorig_RightLeg": "LegShin.R",
    "mixamorig_RightFoot": "Foot.R",
    "mixamorig_RightToeBase": "FootToe.R"
}

func _init():
    var nv_path := "res://assets/characters/ps1_night_vision_operator/NVoperatorsoldier.glb"
    var p := load(nv_path) as PackedScene
    var inst := p.instantiate()
    var skel: Skeleton3D = inst.find_child("Skeleton3D", true, false)
    
    print("Testing PS1 Bone Mapping:")
    var matched := 0
    for mix_bone in MIXAMO_TO_PS1_MAP.keys():
        var ps1_bone: String = MIXAMO_TO_PS1_MAP[mix_bone]
        var idx := skel.find_bone(ps1_bone)
        if idx != -1:
            matched += 1
            print("  [OK] ", mix_bone, " -> ", ps1_bone, " (index ", idx, ")")
        else:
            print("  [FAIL] ", mix_bone, " -> ", ps1_bone)
            
    print("MATCHED: ", matched, " / ", MIXAMO_TO_PS1_MAP.size())
    quit()
