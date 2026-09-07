class_name SocomTransportFactory
extends RefCounted

const Deployment := preload("res://scripts/network/socom_multiplayer_deployment_profile.gd")
const Invite := preload("res://scripts/network/socom_match_invite.gd")
const CAPACITY_PATH := "res://config/network/websocket_capacity.json"

## Creates a candidate. Only the session coordinator installs it into MultiplayerAPI.
static func host(transport: String, port: int, max_players: int) -> Dictionary:
	if transport == Deployment.TRANSPORT_WEBSOCKET:
		var peer := WebSocketMultiplayerPeer.new()
		configure_websocket(peer)
		var bind_address := OS.get_environment("SOCOM_SERVER_BIND_ADDRESS")
		if bind_address.is_empty():
			bind_address = "*"
		return _result(peer.create_server(port, bind_address), peer, transport, "ws://%s:%d" % [bind_address, port])
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
	configure_websocket(peer)
	return _result(peer.create_client(endpoint), peer, Deployment.TRANSPORT_WEBSOCKET, endpoint)

static func configure_websocket(peer: WebSocketMultiplayerPeer) -> void:
	var profile: Variant = JSON.parse_string(FileAccess.get_file_as_string(CAPACITY_PATH))
	if not profile is Dictionary:
		profile = {}
	# Admission includes the normalized map. Engine defaults are smaller than
	# Relic Depot; configure both endpoints before creating any connected peer.
	peer.inbound_buffer_size = clampi(int(profile.get("inbound_buffer_bytes", 2097152)), 262144, 4194304)
	peer.outbound_buffer_size = clampi(int(profile.get("outbound_buffer_bytes", 2097152)), 262144, 4194304)
	peer.max_queued_packets = clampi(int(profile.get("max_queued_packets", 4096)), 64, 4096)

static func _result(error: Error, peer: MultiplayerPeer, transport: String, endpoint: String) -> Dictionary:
	return {"error": error, "peer": peer, "transport": transport, "endpoint": endpoint,
		"message": error_string(error)}
