extends SceneTree

const Composer := preload("res://scripts/labs/animation_layer_composer.gd")
const STANDING_SOURCE := "res://assets/animations/mixamo/Lite Rifle Pack/idle.fbx"
const CROUCH_AIM_SOURCE := "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/idle crouching.fbx"
const OUTPUT := "res://assets/animations/authored/standing_legs_crouch_idle_aim.tres"


func _initialize() -> void:
	var standing := _animation_from_scene(STANDING_SOURCE)
	var crouch_aim := _animation_from_scene(CROUCH_AIM_SOURCE)
	if standing == null or crouch_aim == null:
		push_error("STANDING_CROUCH_AIM_BUILD FAIL source animation missing")
		quit(1)
		return
	var composite: Animation = Composer.new().compose({
		"lower_body": standing,
		"torso": crouch_aim,
		"left_arm": crouch_aim,
		"right_arm": crouch_aim,
		"head": crouch_aim,
	}, 30.0)
	if composite == null or composite.get_track_count() == 0:
		push_error("STANDING_CROUCH_AIM_BUILD FAIL composite is empty")
		quit(1)
		return
	composite.resource_name = "standing_legs_crouch_idle_aim"
	composite.loop_mode = Animation.LOOP_LINEAR
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://assets/animations/authored")
	)
	var save_error := ResourceSaver.save(composite, OUTPUT)
	if save_error != OK:
		push_error("STANDING_CROUCH_AIM_BUILD FAIL %s" % error_string(save_error))
		quit(1)
		return
	print(
		"STANDING_CROUCH_AIM_BUILD PASS path=%s tracks=%d duration=%.3f"
		% [OUTPUT, composite.get_track_count(), composite.length]
	)
	quit(0)


func _animation_from_scene(path: String) -> Animation:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var instance := packed.instantiate()
	var player := _find_animation_player(instance)
	if player == null:
		instance.free()
		return null
	var chosen: Animation
	for animation_name in player.get_animation_list():
		if animation_name == &"RESET":
			continue
		chosen = player.get_animation(animation_name)
		if chosen != null:
			chosen = chosen.duplicate(true)
			break
	instance.free()
	return chosen


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
