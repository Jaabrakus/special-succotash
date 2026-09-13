class_name SocomOperatorCharacterSelection
extends RefCounted

const PATH := "res://config/operator_character.json"

static func apply(owner_node: Node3D) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary or not bool(data.get("enabled", false)):
		return
	var previous := owner_node.get_node_or_null("TrooperModel") as Node3D
	if previous != null and previous.get_meta("socom_modern_character", false):
		return
	var scene := load(String(data.get("scene", ""))) as PackedScene
	if scene == null:
		push_warning("Selected character unavailable; retaining original operator")
		return
	var candidate := scene.instantiate() as Node3D
	if candidate == null or candidate.find_children("*", "Skeleton3D", true, false).size() != 1:
		if candidate != null:
			candidate.free()
		push_warning("Selected character has no unique skeleton; retaining original operator")
		return
	if previous != null:
		candidate.transform = previous.transform
		owner_node.remove_child(previous)
		previous.free()
	else:
		candidate.scale = Vector3.ONE * 62.0
		candidate.rotation.y = PI
	candidate.name = "TrooperModel"
	owner_node.add_child(candidate)
