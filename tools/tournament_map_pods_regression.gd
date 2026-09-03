extends SceneTree

const ArenaCoordinator := preload("res://scripts/network/socom_multi_arena_coordinator.gd")
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MultiplayerScene := preload("res://multiplayer_slice.tscn")

const TOURNAMENT_SETTING := "socom/session/tournament_mode"
const SELECTED_MAP_SETTING := "socom/session/selected_map_document"
const TOURNAMENT_MAP_PATH := "res://config/maps/painterly_coastal_village_2v2.json"
const EXPECTED_ARENA_OFFSETS := [
	Vector3(0.0, 0.0, 0.0),
	Vector3(-300.0, 0.0, -300.0),
	Vector3(0.0, 0.0, -300.0),
	Vector3(300.0, 0.0, -300.0),
	Vector3(-300.0, 0.0, 0.0),
	Vector3(300.0, 0.0, 0.0),
	Vector3(-300.0, 0.0, 300.0),
	Vector3(0.0, 0.0, 300.0),
]

var _frames := 0


func _init() -> void:
	var map_document := MapDocument.load_path(TOURNAMENT_MAP_PATH)
	assert(not map_document.is_empty(), "Tournament pod regression map must load")
	ProjectSettings.set_setting(SELECTED_MAP_SETTING, map_document)
	ProjectSettings.set_setting(TOURNAMENT_SETTING, true)
	change_scene_to_file("res://multiplayer_slice.tscn")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 20:
		return false
	var slice: Node = current_scene
	assert(slice != null, "Tournament scene must boot")
	assert(slice.multiplayer.is_server(), "Focused pod fixture must exercise the server branch")
	assert(slice.tournament_arena_worlds.is_empty(), "Tournament startup must not eagerly clone arena maps")
	slice.receive_tournament_arena_layout()
	assert(slice.tournament_arena_worlds.is_empty(), "Arena layout RPC must not clone maps on its receiver")
	slice.call("_ensure_tournament_arena_worlds")
	assert(slice.tournament_arena_worlds.size() == 7, "A 32-player tournament needs seven cloned arena pods")
	assert(slice.active_map_root != null, "Arena zero must retain the base multiplayer map")
	assert(slice.active_map_root.position == EXPECTED_ARENA_OFFSETS[0], "Arena zero base map must remain at the origin")
	var base_collision_count: int = slice.active_map_root.find_children("*", "CollisionShape3D", true, false).size()
	assert(base_collision_count > 0, "Arena zero base map must contain collision")
	var unique_offsets := {slice.active_map_root.position: true}
	for pod_index in slice.tournament_arena_worlds.size():
		var arena_id: int = pod_index + 1
		var pod: Node3D = slice.tournament_arena_worlds[pod_index]
		var expected_offset: Vector3 = EXPECTED_ARENA_OFFSETS[arena_id]
		assert(pod.name == "TournamentArenaPod_%d" % arena_id, "Pod order must match its arena id")
		assert(pod.position == expected_offset, "Arena %d pod must use its exact coordinator offset" % arena_id)
		assert(pod.position == ArenaCoordinator.get_arena_world_offset(arena_id), "Arena %d pod and coordinator must agree" % arena_id)
		assert(not unique_offsets.has(pod.position), "Arena %d pod offset must be unique" % arena_id)
		unique_offsets[pod.position] = true
		var collision_count := pod.find_children("*", "CollisionShape3D", true, false).size()
		assert(collision_count == base_collision_count, "Arena %d pod must clone the base map collision set" % arena_id)
	assert(unique_offsets.size() == ArenaCoordinator.MAX_CONCURRENT_ARENAS, "Base map plus seven pods need eight unique transforms")
	_assert_client_assignment_uses_one_map_root(slice.active_map_document)
	print("TOURNAMENT_MAP_PODS_REGRESSION PASS")
	ProjectSettings.set_setting(TOURNAMENT_SETTING, false)
	ProjectSettings.set_setting(SELECTED_MAP_SETTING, {})
	quit(0)
	return true


func _assert_client_assignment_uses_one_map_root(map_document: Dictionary) -> void:
	# The concrete scene exposes these methods as authority-only, call-remote RPCs.
	# Calling them directly models the receiver without opening a transport socket.
	var client_slice: Node = MultiplayerScene.instantiate()
	client_slice.active_map_document = map_document.duplicate(true)
	var client_map_root := Node3D.new()
	client_map_root.name = "ActiveMultiplayerMap"
	client_slice.add_child(client_map_root)
	client_slice.active_map_root = client_map_root
	client_slice.receive_tournament_arena_layout()
	assert(client_slice.tournament_mode_enabled, "Client layout receiver must enable tournament mode")
	assert(client_slice.tournament_arena_worlds.is_empty(), "Client layout receiver must keep zero cloned pods")
	var assigned_arena_id := 7
	client_slice.receive_tournament_assignment(77, 0, Vector3.ZERO, assigned_arena_id)
	assert(client_slice.active_map_root == client_map_root, "Client assignment must reuse its one active map root")
	assert(client_map_root.position == ArenaCoordinator.get_arena_world_offset(assigned_arena_id), "Client map root must move to its assigned arena offset")
	assert(client_slice.tournament_arena_worlds.is_empty(), "Client assignment must not create cloned pods")
	client_slice.free()
