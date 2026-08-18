extends SceneTree

const DRIVER_SCRIPT := preload("res://scripts/player/operator_animation_driver.gd")


func _init() -> void:
    _run.call_deferred()


func _run() -> void:
    var driver = DRIVER_SCRIPT.new()
    root.add_child(driver)
    await process_frame
    await process_frame
    var library: AnimationLibrary = driver.animation_player.get_animation_library("")
    for clip_name in [&"run_forward", &"run_right", &"run_left", &"aim_idle"]:
        var animation: Animation = library.get_animation(clip_name)
        print("UPPER_TRACK_AUDIT ", clip_name, " tracks=", animation.get_track_count())
        for track in range(animation.get_track_count()):
            var path := str(animation.track_get_path(track))
            if "mixamorig_Hips" in path and animation.track_get_type(track) == Animation.TYPE_ROTATION_3D:
                var hip_rotation: Quaternion = animation.track_get_key_value(track, 0)
                print("HIP_ROTATION_AUDIT ", clip_name, " first_key_euler_deg=", hip_rotation.get_euler() * 180.0 / PI)
            if _is_upper_body_path(path):
                print("UPPER_TRACK ", clip_name, " ", path)
    driver.queue_free()
    quit(0)


func _is_upper_body_path(path: String) -> bool:
    for token in ["Spine", "Neck", "Head", "Shoulder", "Arm", "ForeArm", "Hand"]:
        if token in path:
            return true
    return false
