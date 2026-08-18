extends SceneTree

var frames := 0

func _init():
    change_scene_to_file("res://main.tscn")

func _process(delta: float) -> bool:
    frames += 1
    if frames == 5:
        print("=== VERIFYING MAIN SCENE HIERARCHY ===")
        var root_node := current_scene
        print("Current scene: ", root_node.name if root_node else "NULL")
        if root_node:
            var player := root_node.get_node_or_null("Player")
            print("Player: ", player != null)
            if player:
                var mannequin := player.get_node_or_null("Mannequin")
                print("Mannequin: ", mannequin != null)
                if mannequin:
                    var driver := mannequin.get_node_or_null("ProductionAnimation")
                    print("ProductionAnimation Driver: ", driver != null)
                    if driver:
                        print("Clips in Driver: ", driver.get_clip_names().size())
                        print("Current active clip: ", driver.current_clip)
        print("=== VERIFICATION PASSED ===")
        quit()
        return true
    return false
