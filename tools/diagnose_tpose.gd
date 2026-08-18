extends SceneTree

var frames := 0

func _init():
    change_scene_to_file("res://main.tscn")

func _process(delta: float) -> bool:
    frames += 1
    var player := current_scene.get_node_or_null("Player") as SocomTestPlayer
    var mannequin := player.get_node_or_null("Mannequin") if player else null
    var driver: SocomOperatorAnimationDriver = mannequin.get_node_or_null("ProductionAnimation") if mannequin else null
    
    if driver and driver.skeleton:
        var skel := driver.skeleton
        var hips_idx := skel.find_bone("mixamorig_Hips")
        var hips_pos := skel.get_bone_pose(hips_idx).origin * 55.0
        
        if frames == 5:
            print("Standing Hips Height: ", hips_pos.y, "m | Clip: ", driver.current_clip)
            # Switch to Crouch
            player.posture = SocomTestPlayer.MotionState.CROUCHED
            player.motion_state = SocomTestPlayer.MotionState.CROUCHED
        elif frames == 15:
            print("Crouch Hips Height:   ", hips_pos.y, "m | Clip: ", driver.current_clip)
            # Switch to Prone
            player.posture = SocomTestPlayer.MotionState.PRONE
            player.motion_state = SocomTestPlayer.MotionState.PRONE
        elif frames == 25:
            print("Prone Hips Height:    ", hips_pos.y, "m | Clip: ", driver.current_clip)
            print("=== SKELETON_ROOT DUMMY VISIBLE: ", mannequin.skeleton_root.visible if mannequin.skeleton_root else "NULL")
            quit()
            return true
    return false
