extends Node3D

var operators: Dictionary = {}
var session_active := true
var round_index := 1

func is_lobby_warmup_active() -> bool:
	return false

func is_peer_gameplay_action_allowed(peer_id: int) -> bool:
	return operators.has(peer_id)
