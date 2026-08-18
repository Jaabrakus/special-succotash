extends SceneTree

func _init():
    var ap := AnimationPlayer.new()
    var tree := AnimationTree.new()
    
    var lib := AnimationLibrary.new()
    var anim := Animation.new()
    anim.length = 1.0
    lib.add_animation("anim_a", anim)
    lib.add_animation("anim_b", anim)
    ap.add_animation_library("", lib)
    
    var blend_tree := AnimationNodeBlendTree.new()
    var trans := AnimationNodeTransition.new()
    trans.input_count = 2
    trans.set_input_name(0, &"anim_a")
    trans.set_input_name(1, &"anim_b")
    blend_tree.add_node(&"trans", trans)
    
    var node_a := AnimationNodeAnimation.new()
    node_a.animation = &"anim_a"
    blend_tree.add_node(&"anim_a", node_a)
    blend_tree.connect_node(&"trans", 0, &"anim_a")
    
    var node_b := AnimationNodeAnimation.new()
    node_b.animation = &"anim_b"
    blend_tree.add_node(&"anim_b", node_b)
    blend_tree.connect_node(&"trans", 1, &"anim_b")
    
    blend_tree.connect_node(&"output", 0, &"trans")
    
    var root_node := Node.new()
    root_node.add_child(ap)
    root_node.add_child(tree)
    root.add_child(root_node)

    tree.anim_player = tree.get_path_to(ap)
    tree.tree_root = blend_tree
    tree.active = true
    
    print("Default current_state: ", tree.get("parameters/trans/current_state"))
    
    # Test setting transition_request
    tree.set("parameters/trans/transition_request", &"anim_b")
    print("After request anim_b, transition_request: ", tree.get("parameters/trans/transition_request"))
    print("current_state: ", tree.get("parameters/trans/current_state"))
    
    root_node.queue_free()
    quit()
