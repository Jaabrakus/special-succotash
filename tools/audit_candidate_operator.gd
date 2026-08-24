extends SceneTree

## Read-only candidate-character audit. This does not change the playable skin.


func _initialize() -> void:
	var candidate_path := "res://counter-strike-urban/source/Counter Strike Urban.fbx"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--candidate="):
			candidate_path = argument.trim_prefix("--candidate=")
	var packed := load(candidate_path) as PackedScene
	if packed == null:
		push_error("CANDIDATE_OPERATOR_AUDIT could not load %s" % candidate_path)
		quit(1)
		return
	var instance := packed.instantiate()
	root.add_child(instance)
	var skeleton := _find_skeleton(instance)
	var animation_players: Array[AnimationPlayer] = []
	var meshes: Array[MeshInstance3D] = []
	_collect_nodes(instance, animation_players, meshes)
	print("CANDIDATE_OPERATOR path=%s skeleton=%s bones=%d meshes=%d players=%d" % [
		candidate_path,
		str(skeleton != null),
		skeleton.get_bone_count() if skeleton != null else 0,
		meshes.size(),
		animation_players.size(),
	])
	if skeleton != null:
		for index in range(skeleton.get_bone_count()):
			print("CANDIDATE_BONE %d %s" % [index, skeleton.get_bone_name(index)])
	for mesh in meshes:
		var aabb := mesh.get_aabb()
		print("CANDIDATE_MESH %s size=%s surfaces=%d" % [
			mesh.name,
			str(aabb.size),
			mesh.mesh.get_surface_count() if mesh.mesh != null else 0,
		])
	for player in animation_players:
		print("CANDIDATE_ANIMATIONS %s %s" % [
			player.name,
			str(player.get_animation_list()),
		])
	instance.queue_free()
	quit(0)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _collect_nodes(
	node: Node,
	animation_players: Array[AnimationPlayer],
	meshes: Array[MeshInstance3D]
) -> void:
	if node is AnimationPlayer:
		animation_players.append(node as AnimationPlayer)
	elif node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_nodes(child, animation_players, meshes)
