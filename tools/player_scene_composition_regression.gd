extends SceneTree

## Guards the first editor-visible gameplay composition boundary. Runtime code
## may configure the player, but it must not rebuild these stable child nodes.

const PLAYER_SCENE_PATH := "res://scenes/player/operator_player.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for action in [
		&"move_forward", &"move_back", &"move_left", &"move_right",
		&"jump", &"dive", &"crouch", &"peek_left", &"peek_right",
	]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var packed := load(PLAYER_SCENE_PATH) as PackedScene
	_expect(packed != null, "operator player is a reusable PackedScene")
	if packed == null:
		_finish()
		return
	var player := packed.instantiate() as CharacterBody3D
	player.set_physics_process(false)
	root.add_child(player)
	await process_frame
	_expect(player != null, "operator player root is the authoritative CharacterBody3D")
	if player == null:
		_finish()
		return
	var collider := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var mannequin := player.get_node_or_null("Mannequin") as Node3D
	_expect(
		collider != null and collider.shape is CapsuleShape3D,
		"player collision is visible and editable in the scene"
	)
	_expect(
		mannequin != null and mannequin.get_script() != null,
		"operator visual root is visible and editable in the scene"
	)
	var runtime_source := FileAccess.get_file_as_string(
		"res://scripts/runtime/main_training_world.gd"
	)
	_expect(
		runtime_source.contains("PlayerScene.instantiate()")
		and not runtime_source.contains("var collider := CollisionShape3D.new()")
		and not runtime_source.contains("Mannequin.new()"),
		"training runtime instantiates the scene instead of rebuilding stable children"
	)
	player.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PLAYER_SCENE_CHECK PASS %s" % label)
	else:
		failures.append(label)
		push_error("PLAYER_SCENE_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("PLAYER_SCENE_COMPOSITION_REGRESSION PASS")
		quit(0)
	else:
		print("PLAYER_SCENE_COMPOSITION_REGRESSION FAIL %s" % [failures])
		quit(1)
