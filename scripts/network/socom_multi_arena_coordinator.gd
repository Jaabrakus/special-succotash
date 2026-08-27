class_name SocomMultiArenaCoordinator
extends RefCounted

## Coordinates 8 concurrent 2v2 Gunfight sub-matches across spatially isolated arena pods.

signal stage_completed(advancing_pairs: Array[int])
signal grand_championship_completed(champion_pair_id: int)

const ARENA_COUNT := 8
const ARENA_GRID_SPACING := 300.0
const SubMatchScript := preload("res://scripts/network/socom_arena_sub_match.gd")

# Offsets for 8 arenas in 3D world space (4x2 grid, 300m separation)
var arena_offsets: Array[Vector3] = [
	Vector3(0.0, 0.0, 0.0),
	Vector3(ARENA_GRID_SPACING, 0.0, 0.0),
	Vector3(ARENA_GRID_SPACING * 2.0, 0.0, 0.0),
	Vector3(ARENA_GRID_SPACING * 3.0, 0.0, 0.0),
	Vector3(0.0, 0.0, ARENA_GRID_SPACING),
	Vector3(ARENA_GRID_SPACING, 0.0, ARENA_GRID_SPACING),
	Vector3(ARENA_GRID_SPACING * 2.0, 0.0, ARENA_GRID_SPACING),
	Vector3(ARENA_GRID_SPACING * 3.0, 0.0, ARENA_GRID_SPACING),
]

var active_sub_matches: Dictionary = {} # arena_id -> SubMatchScript instance
var current_stage: String = "ROUND OF 16"
var tournament_active: bool = false
var rounds_to_win: int = 3
var champion_pair_id: int = -1


func initialize_tournament_stage(
	participating_pairs: Array,
	lobby_get_members_fn: Callable,
	target_rounds: int = 3
) -> Array[Dictionary]:
	active_sub_matches.clear()
	tournament_active = true
	champion_pair_id = -1
	rounds_to_win = target_rounds
	
	var pairs := participating_pairs.duplicate()
	
	if pairs.size() > 8:
		current_stage = "ROUND OF 16"
	elif pairs.size() > 4:
		current_stage = "QUARTERFINALS"
	elif pairs.size() > 2:
		current_stage = "SEMIFINALS"
	else:
		current_stage = "GRAND FINALS"
	
	var matchups_created: Array[Dictionary] = []
	var arena_idx := 0
	var i := 0
	while i < pairs.size() and arena_idx < ARENA_COUNT:
		var p_a: int = int(pairs[i])
		var p_b: int = int(pairs[i + 1]) if i + 1 < pairs.size() else -1
		
		if p_b == -1:
			i += 2
			continue
			
		var members_a: Array = lobby_get_members_fn.call(p_a)
		var members_b: Array = lobby_get_members_fn.call(p_b)
		var peers_a: Array[int] = []
		for m in members_a: peers_a.append(int((m as Dictionary).get("peer_id", 0)))
		var peers_b: Array[int] = []
		for m in members_b: peers_b.append(int((m as Dictionary).get("peer_id", 0)))
		
		var sub_match: RefCounted = SubMatchScript.new()
		sub_match.call(
			"initialize",
			arena_idx,
			arena_offsets[arena_idx],
			p_a,
			p_b,
			peers_a,
			peers_b,
			rounds_to_win
		)
		active_sub_matches[arena_idx] = sub_match
		matchups_created.append(sub_match.call("get_snapshot"))
		arena_idx += 1
		i += 2
		
	return matchups_created


func get_arena_for_peer(peer_id: int) -> RefCounted:
	for arena_id in active_sub_matches:
		var sub_match: RefCounted = active_sub_matches[arena_id]
		if sub_match != null and bool(sub_match.call("has_peer", peer_id)):
			return sub_match
	return null


func advance_all_clocks(delta: float) -> Array[int]:
	var timed_out_arenas: Array[int] = []
	for arena_id in active_sub_matches:
		var sub_match: RefCounted = active_sub_matches[arena_id]
		if sub_match != null:
			var res: Dictionary = sub_match.call("advance_clock", delta)
			if bool(res.get("timeout", false)):
				timed_out_arenas.append(int(arena_id))
	return timed_out_arenas


func handle_peer_eliminated(victim_peer_id: int, is_peer_alive_fn: Callable) -> Dictionary:
	var sub_match: RefCounted = get_arena_for_peer(victim_peer_id)
	if sub_match == null:
		return {"handled": false}
	var res: Dictionary = sub_match.call("on_operator_eliminated", victim_peer_id, is_peer_alive_fn)
	res["handled"] = true
	
	if bool(res.get("match_completed", false)):
		_check_stage_progression()
		
	return res


func _check_stage_progression() -> void:
	var all_completed := true
	var advancing_pairs: Array[int] = []
	for arena_id in active_sub_matches:
		var sub_match: RefCounted = active_sub_matches[arena_id]
		if sub_match != null:
			var completed: bool = bool(sub_match.get("match_completed"))
			var win_p: int = int(sub_match.get("winner_pair_id"))
			if not completed:
				all_completed = false
			elif win_p >= 0:
				advancing_pairs.append(win_p)
					
	if all_completed:
		if advancing_pairs.size() == 1:
			tournament_active = false
			champion_pair_id = advancing_pairs[0]
			grand_championship_completed.emit(champion_pair_id)
		else:
			stage_completed.emit(advancing_pairs)


func build_multi_arena_geometry(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "MultiArenaWorldGrid"
	parent.add_child(root)
	
	for idx in range(ARENA_COUNT):
		var offset := arena_offsets[idx]
		var arena_node := Node3D.new()
		arena_node.name = "ArenaPod_%02d" % (idx + 1)
		arena_node.position = offset
		root.add_child(arena_node)
		
		# Arena Floor (26m x 26m combat zone)
		_create_box(arena_node, "Floor", Vector3(26.0, 0.25, 26.0), Vector3(0.0, -0.125, 0.0), Color(0.24, 0.26, 0.30))
		# Center tactical cover
		_create_box(arena_node, "CenterCover", Vector3(6.0, 1.2, 0.8), Vector3(0.0, 0.6, 0.0), Color(0.42, 0.38, 0.32))
		# Left & Right flanking cover
		_create_box(arena_node, "LeftCover", Vector3(0.8, 2.2, 5.0), Vector3(-6.0, 1.1, 0.0), Color(0.30, 0.35, 0.40))
		_create_box(arena_node, "RightCover", Vector3(0.8, 2.2, 5.0), Vector3(6.0, 1.1, 0.0), Color(0.30, 0.35, 0.40))
		# Perimeter boundary walls (prevents falling off or cross-arena wander)
		_create_box(arena_node, "WallNorth", Vector3(26.0, 3.5, 0.5), Vector3(0.0, 1.75, -13.0), Color(0.18, 0.20, 0.24))
		_create_box(arena_node, "WallSouth", Vector3(26.0, 3.5, 0.5), Vector3(0.0, 1.75, 13.0), Color(0.18, 0.20, 0.24))
		_create_box(arena_node, "WallWest", Vector3(0.5, 3.5, 26.0), Vector3(-13.0, 1.75, 0.0), Color(0.18, 0.20, 0.24))
		_create_box(arena_node, "WallEast", Vector3(0.5, 3.5, 26.0), Vector3(13.0, 1.75, 0.0), Color(0.18, 0.20, 0.24))


func _create_box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	var mesh_inst := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_inst.mesh = box_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
