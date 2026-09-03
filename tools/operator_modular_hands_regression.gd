extends SceneTree

const MODULAR_GLB := (
	"res://assets/characters/operator_rig_v2/"
	+ "operator_autorigpro_gameplay_library_modular_hands_humanoid.glb"
)


func _init() -> void:
	var packed := load(MODULAR_GLB) as PackedScene
	_assert(packed != null, "modular GLB loads")
	if packed == null:
		quit(1)
		return
	var instance := packed.instantiate()
	root.add_child(instance)
	var meshes: Array[MeshInstance3D] = []
	var skeletons: Array[Skeleton3D] = []
	var players: Array[AnimationPlayer] = []
	_collect(instance, meshes, skeletons, players)
	_assert(meshes.size() == 15, "fourteen sections become thirteen body plus two hands")
	_assert(skeletons.size() == 1, "one shared native skeleton")
	var left := _mesh_named(meshes, "OperatorHand_L")
	var right := _mesh_named(meshes, "OperatorHand_R")
	_assert(left != null, "left modular hand exists")
	_assert(right != null, "right modular hand exists")
	if left != null and right != null:
		_assert(left.skeleton == right.skeleton, "hands share the same skeleton path")
		_assert(not left.skeleton.is_empty(), "hands are skinned, not independently transformed")
	var finger_bones := 0
	if not skeletons.is_empty():
		for bone_index in skeletons[0].get_bone_count():
			var name := String(skeletons[0].get_bone_name(bone_index)).to_lower()
			if (
				("handthumb" in name)
				or ("handindex" in name)
				or ("handmiddle" in name)
				or ("handring" in name)
				or ("handpinky" in name)
			):
				finger_bones += 1
	_assert(finger_bones >= 30, "authored finger chains survive Godot export")
	var action_count := 0
	for player in players:
		action_count = maxi(action_count, player.get_animation_list().size())
	_assert(action_count >= 80, "gameplay action library survives modular split")
	print(
		"OPERATOR_MODULAR_HANDS_PASS meshes=%d finger_bones=%d actions=%d" % [
			meshes.size(),
			finger_bones,
			action_count,
		]
	)
	quit(0)


func _collect(
	node: Node,
	meshes: Array[MeshInstance3D],
	skeletons: Array[Skeleton3D],
	players: Array[AnimationPlayer]
) -> void:
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	elif node is Skeleton3D:
		skeletons.append(node as Skeleton3D)
	elif node is AnimationPlayer:
		players.append(node as AnimationPlayer)
	for child in node.get_children():
		_collect(child, meshes, skeletons, players)


func _mesh_named(meshes: Array[MeshInstance3D], expected: String) -> MeshInstance3D:
	for mesh in meshes:
		if String(mesh.name).begins_with(expected):
			return mesh
	return null


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("OPERATOR_MODULAR_HANDS_FAIL %s" % message)
	quit(1)
