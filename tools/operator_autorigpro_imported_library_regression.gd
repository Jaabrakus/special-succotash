extends SceneTree

const LIBRARY_GLB := (
	"res://assets/characters/operator_rig_v2/"
	+ "operator_autorigpro_gameplay_library_humanoid.glb"
)


func _init() -> void:
	var packed := load(LIBRARY_GLB) as PackedScene
	if packed == null:
		push_error("OPERATOR_ARP_IMPORTED_LIBRARY_FAIL resource does not load")
		quit(1)
		return
	var instance := packed.instantiate()
	root.add_child(instance)
	var players: Array[AnimationPlayer] = []
	_collect_players(instance, players)
	if players.is_empty():
		push_error("OPERATOR_ARP_IMPORTED_LIBRARY_FAIL no AnimationPlayer")
		quit(1)
		return
	var found := false
	for player in players:
		var names := player.get_animation_list()
		print("OPERATOR_ARP_IMPORTED_ACTIONS count=%d names=%s" % [names.size(), names])
		found = found or names.has(&"native__jump")
	if not found:
		push_error("OPERATOR_ARP_IMPORTED_LIBRARY_FAIL Godot jump-loop alias missing")
		quit(1)
		return
	print("OPERATOR_ARP_IMPORTED_LIBRARY_PASS")
	quit(0)


func _collect_players(node: Node, output: Array[AnimationPlayer]) -> void:
	if node is AnimationPlayer:
		output.append(node as AnimationPlayer)
	for child in node.get_children():
		_collect_players(child, output)
