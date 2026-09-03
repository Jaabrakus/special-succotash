extends "res://scripts/network/socom_multiplayer_session.gd"

## Extends the canonical multiplayer session with server-owned duo selection.
## The HUD emits intent only. SocomLobbyState validates the authoritative
## phase, peer membership, pair range, and two-player capacity.


func _choose_lobby_pair(pair_id: int) -> void:
	var peer_id := multiplayer.get_unique_id()
	if multiplayer.is_server():
		_server_set_lobby_pair(peer_id, pair_id)
	else:
		request_lobby_pair.rpc_id(1, pair_id)


func _server_set_lobby_pair(peer_id: int, pair_id: int) -> void:
	if lobby.set_pair(peer_id, pair_id):
		_broadcast_lobby()


@rpc("any_peer", "call_remote", "reliable")
func request_lobby_pair(pair_id: int) -> void:
	if multiplayer.is_server():
		_server_set_lobby_pair(multiplayer.get_remote_sender_id(), pair_id)
