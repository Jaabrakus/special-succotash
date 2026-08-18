extends SceneTree

const CLIPS := [
    "res://assets/animations/mixamo/Prone Forward.fbx",
    "res://assets/animations/mixamo/Moving Backward In Prone Position.fbx",
    "res://assets/animations/mixamo/Moving Backward In Crawl Position.fbx",
]

func _init() -> void:
    for path in CLIPS:
        var packed := load(path) as PackedScene
        print("CLIP ", path, " loaded=", packed != null)
        if packed == null:
            continue
        var instance := packed.instantiate()
        var player := _find_animation_player(instance)
        if player == null:
            print("  no AnimationPlayer")
            instance.free()
            continue
        print("  list=", player.get_animation_list())
        for animation_name in player.get_animation_list():
            if animation_name == &"RESET":
                continue
            var animation := player.get_animation(animation_name)
            var position_tracks := 0
            var rotation_tracks := 0
            var bone_names: Dictionary = {}
            for track_index in range(animation.get_track_count()):
                var track_path := str(animation.track_get_path(track_index))
                var raw_bone := track_path.split(":")[-1]
                bone_names[raw_bone] = true
                if animation.track_get_type(track_index) == Animation.TYPE_POSITION_3D:
                    position_tracks += 1
                elif animation.track_get_type(track_index) == Animation.TYPE_ROTATION_3D:
                    rotation_tracks += 1
            print(
                "  animation=", animation_name,
                " length=", animation.length,
                " tracks=", animation.get_track_count(),
                " position=", position_tracks,
                " rotation=", rotation_tracks,
                " bones=", bone_names.size()
            )
            print("  bone sample=", bone_names.keys().slice(0, 8))
        instance.free()
    quit()

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node
    for child in node.get_children():
        var result := _find_animation_player(child)
        if result != null:
            return result
    return null
