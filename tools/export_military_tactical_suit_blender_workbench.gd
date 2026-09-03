extends SceneTree

const SUIT := preload(
	"res://assets/characters/military_tactical_suit/military_tactical_suit_production.glb"
)
const OUTPUT_PATH := (
	"res://assets/characters/military_tactical_suit/"
	+ "military_tactical_suit_blender_workbench.glb"
)


func _initialize() -> void:
	var suit := SUIT.instantiate() as Node3D
	if suit == null:
		push_error("SUIT_BLENDER_WORKBENCH_EXPORT FAIL: could not instantiate suit")
		quit(1)
		return
	root.add_child(suit)
	var skeleton := _find_skeleton(suit)
	if skeleton == null:
		push_error("SUIT_BLENDER_WORKBENCH_EXPORT FAIL: skeleton missing")
		quit(1)
		return
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var append_error := document.append_from_scene(suit, state)
	if append_error != OK:
		push_error(
			"SUIT_BLENDER_WORKBENCH_EXPORT FAIL: append error %d" % append_error
		)
		quit(1)
		return
	var write_error := document.write_to_filesystem(state, OUTPUT_PATH)
	if write_error != OK:
		push_error(
			"SUIT_BLENDER_WORKBENCH_EXPORT FAIL: write error %d" % write_error
		)
		quit(1)
		return
	print(
		"SUIT_BLENDER_WORKBENCH_EXPORT PASS path=%s bones=%d"
		% [OUTPUT_PATH, skeleton.get_bone_count()]
	)
	quit(0)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
