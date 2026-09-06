class_name SocomTransportFactory
extends RefCounted

const Deployment := preload("res://scripts/network/socom_multiplayer_deployment_profile.gd")
const Invite := preload("res://scripts/network/socom_match_invite.gd")

## Creates a candidate. Only the session coordinator installs it into MultiplayerAPI.
static func host(transport: String, port: int, max_players: int) -> Dictionary:
	if transport == Deployment.TRANSPORT_WEBSOCKET:
		var peer := WebSocketMultiplayerPeer.new()
		return _result(peer.create_server(port), peer, transport, "ws://0.0.0.0:%d" % port)
	var peer := ENetMultiplayerPeer.new()
	return _result(peer.create_server(port, max_players), peer, Deployment.TRANSPORT_ENET, "0.0.0.0:%d" % port)

static func connect_enet(address: String, port: int) -> Dictionary:
	var target := Invite.parse(address, port)
	if not bool(target.get("ok", false)):
		return {"error": ERR_INVALID_PARAMETER, "message": target.get("message", "Invalid invite code.")}
	var host_address := String(target.get("address", "127.0.0.1"))
	var host_port := int(target.get("port", port))
	var peer := ENetMultiplayerPeer.new()
	return _result(peer.create_client(host_address, host_port), peer, Deployment.TRANSPORT_ENET,
		"%s:%d" % [host_address, host_port])

static func connect_websocket(address: String, port: int, require_secure: bool) -> Dictionary:
	var target := Deployment.websocket_endpoint(address, port, require_secure)
	if not bool(target.get("ok", false)):
		return {"error": ERR_INVALID_PARAMETER, "message": target.get("message", "Invalid WebSocket server address.")}
	var endpoint := String(target.url)
	var peer := WebSocketMultiplayerPeer.new()
	return _result(peer.create_client(endpoint), peer, Deployment.TRANSPORT_WEBSOCKET, endpoint)

static func _result(error: Error, peer: MultiplayerPeer, transport: String, endpoint: String) -> Dictionary:
	return {"error": error, "peer": peer, "transport": transport, "endpoint": endpoint,
		"message": error_string(error)}
