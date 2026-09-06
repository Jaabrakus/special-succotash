class_name SocomWebRTCSignalingClient
extends Node

## Browser WebRTC transport adapter. The signaling socket only exchanges room,
## SDP, and ICE messages. SocomMultiplayerSession remains the sole lobby and
## gameplay authority owner after the WebRTCMultiplayerPeer is installed.

signal multiplayer_peer_ready(
	peer: WebRTCMultiplayerPeer,
	room_code: String,
	hosting: bool,
	tournament: bool
)
signal room_created(room_code: String)
signal failed(message: String)
signal signaling_lost(message: String)

const PROTOCOL_VERSION := 1
const HEARTBEAT_INTERVAL_MS := 20000
const ROOM_PREFIX := "P2P-"

enum Mode {
	NONE,
	HOST,
	CLIENT,
	TOURNAMENT,
}

var socket := WebSocketPeer.new()
var rtc_peer := WebRTCMultiplayerPeer.new()
var connection_by_peer_id: Dictionary = {}
var mode := Mode.NONE
var room_code := ""
var signaling_url := ""
var ice_servers: Array = []
var socket_state := WebSocketPeer.STATE_CLOSED
var handshake_sent := false
var multiplayer_ready := false
var last_heartbeat_ms := 0


func start_host(url: String, configured_ice_servers: Array) -> Error:
	return _start(url, "", Mode.HOST, configured_ice_servers)


func start_client(url: String, requested_room_code: String, configured_ice_servers: Array) -> Error:
	var normalized_room := normalize_room_code(requested_room_code)
	if not is_room_code(normalized_room):
		return ERR_INVALID_PARAMETER
	return _start(url, normalized_room, Mode.CLIENT, configured_ice_servers)


func start_tournament(url: String, configured_ice_servers: Array) -> Error:
	return _start(url, "", Mode.TOURNAMENT, configured_ice_servers)


func stop() -> void:
	set_process(false)
	if socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		socket.close(1000, "session closed")
	if rtc_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		rtc_peer.close()
	connection_by_peer_id.clear()
	mode = Mode.NONE
	room_code = ""
	handshake_sent = false
	multiplayer_ready = false


func _start(
	url: String,
	requested_room_code: String,
	requested_mode: Mode,
	configured_ice_servers: Array
) -> Error:
	stop()
	signaling_url = url.strip_edges()
	if not _is_valid_signaling_url(signaling_url):
		return ERR_INVALID_PARAMETER
	mode = requested_mode
	room_code = requested_room_code
	ice_servers = configured_ice_servers.duplicate(true)
	socket = WebSocketPeer.new()
	rtc_peer = WebRTCMultiplayerPeer.new()
	var error := socket.connect_to_url(signaling_url)
	if error != OK:
		mode = Mode.NONE
		return error
	socket_state = socket.get_ready_state()
	last_heartbeat_ms = Time.get_ticks_msec()
	set_process(true)
	return OK


func _process(_delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and not handshake_sent:
		handshake_sent = true
		_send({
			"type": (
				"create"
				if mode == Mode.HOST
				else "join_tournament" if mode == Mode.TOURNAMENT else "join"
			),
			"protocol": PROTOCOL_VERSION,
			"room": room_code,
		})
	while state == WebSocketPeer.STATE_OPEN and socket.get_available_packet_count() > 0:
		_handle_packet(socket.get_packet())
	if state == WebSocketPeer.STATE_OPEN:
		var now_ms := Time.get_ticks_msec()
		if now_ms - last_heartbeat_ms >= HEARTBEAT_INTERVAL_MS:
			last_heartbeat_ms = now_ms
			_send({"type": "ping", "protocol": PROTOCOL_VERSION})
	elif state == WebSocketPeer.STATE_CLOSED and socket_state != WebSocketPeer.STATE_CLOSED:
		set_process(false)
		var message := "WebRTC signaling disconnected"
		if not multiplayer_ready:
			failed.emit(message)
		else:
			signaling_lost.emit(message + "; the active peer match can continue")
	socket_state = state


func _handle_packet(packet: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
	if parsed is not Dictionary:
		failed.emit("The signaling service returned an invalid message.")
		return
	var message := parsed as Dictionary
	var message_type := String(message.get("type", ""))
	match message_type:
		"room":
			_configure_multiplayer_peer(message)
		"peer_joined":
			_create_connection(int(message.get("peer_id", 0)), true)
		"peer_left":
			_remove_connection(int(message.get("peer_id", 0)))
		"offer", "answer":
			_apply_remote_description(
				int(message.get("peer_id", 0)),
				message_type,
				String(message.get("sdp", ""))
			)
		"candidate":
			_apply_remote_candidate(message)
		"host_left":
			failed.emit(
				"The tournament host left; return to Quick Match."
				if mode == Mode.TOURNAMENT
				else "The private-match host left the room."
			)
		"error":
			failed.emit(String(message.get("message", "WebRTC signaling failed.")))
		"pong":
			pass


func _configure_multiplayer_peer(message: Dictionary) -> void:
	if multiplayer_ready:
		return
	room_code = normalize_room_code(String(message.get("room", "")))
	var peer_id := int(message.get("peer_id", 0))
	var hosting := bool(message.get("host", false))
	var tournament := bool(message.get("tournament", false))
	var error := rtc_peer.create_server() if hosting else rtc_peer.create_client(peer_id)
	if error != OK:
		failed.emit("Could not initialize WebRTC multiplayer: %s" % error_string(error))
		return
	multiplayer_ready = true
	multiplayer_peer_ready.emit(rtc_peer, room_code, hosting, tournament)
	if hosting:
		room_created.emit(room_code)
	else:
		_create_connection(MultiplayerPeer.TARGET_PEER_SERVER, false)


func _create_connection(remote_peer_id: int, create_offer: bool) -> void:
	if not multiplayer_ready or remote_peer_id <= 0 or rtc_peer.has_peer(remote_peer_id):
		return
	var connection := WebRTCPeerConnection.new()
	var initialize_error := connection.initialize({"iceServers": ice_servers})
	if initialize_error != OK:
		failed.emit("Could not initialize a WebRTC peer: %s" % error_string(initialize_error))
		return
	connection.session_description_created.connect(
		_on_session_description_created.bind(remote_peer_id)
	)
	connection.ice_candidate_created.connect(_on_ice_candidate_created.bind(remote_peer_id))
	var add_error := rtc_peer.add_peer(connection, remote_peer_id)
	if add_error != OK:
		failed.emit("Could not add WebRTC peer %d: %s" % [remote_peer_id, error_string(add_error)])
		return
	connection_by_peer_id[remote_peer_id] = connection
	if create_offer:
		var offer_error := connection.create_offer()
		if offer_error != OK:
			failed.emit("Could not create WebRTC offer: %s" % error_string(offer_error))


func _remove_connection(remote_peer_id: int) -> void:
	if rtc_peer.has_peer(remote_peer_id):
		rtc_peer.remove_peer(remote_peer_id)
	connection_by_peer_id.erase(remote_peer_id)


func _on_session_description_created(
	description_type: String,
	sdp: String,
	remote_peer_id: int
) -> void:
	var connection := connection_by_peer_id.get(remote_peer_id) as WebRTCPeerConnection
	if connection == null:
		return
	var local_error := connection.set_local_description(description_type, sdp)
	if local_error != OK:
		failed.emit("Could not set the local WebRTC description.")
		return
	_send({
		"type": description_type,
		"protocol": PROTOCOL_VERSION,
		"room": room_code,
		"target": remote_peer_id,
		"sdp": sdp,
	})


func _on_ice_candidate_created(
	media: String,
	index: int,
	sdp: String,
	remote_peer_id: int
) -> void:
	_send({
		"type": "candidate",
		"protocol": PROTOCOL_VERSION,
		"room": room_code,
		"target": remote_peer_id,
		"media": media,
		"index": index,
		"sdp": sdp,
	})


func _apply_remote_description(remote_peer_id: int, description_type: String, sdp: String) -> void:
	if sdp.is_empty():
		return
	if not rtc_peer.has_peer(remote_peer_id):
		_create_connection(remote_peer_id, false)
	var connection := connection_by_peer_id.get(remote_peer_id) as WebRTCPeerConnection
	if connection == null:
		return
	var error := connection.set_remote_description(description_type, sdp)
	if error != OK:
		failed.emit("Could not apply the remote WebRTC %s." % description_type)


func _apply_remote_candidate(message: Dictionary) -> void:
	var remote_peer_id := int(message.get("peer_id", 0))
	if not rtc_peer.has_peer(remote_peer_id):
		_create_connection(remote_peer_id, false)
	var connection := connection_by_peer_id.get(remote_peer_id) as WebRTCPeerConnection
	if connection == null:
		return
	var error := connection.add_ice_candidate(
		String(message.get("media", "")),
		int(message.get("index", 0)),
		String(message.get("sdp", ""))
	)
	if error != OK:
		failed.emit("Could not apply a remote WebRTC network candidate.")


func _send(message: Dictionary) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	socket.send_text(JSON.stringify(message))


func _is_valid_signaling_url(url: String) -> bool:
	if OS.has_feature("web"):
		return url.to_lower().begins_with("wss://")
	return url.to_lower().begins_with("wss://") or url.to_lower().begins_with("ws://")


static func normalize_room_code(value: String) -> String:
	return value.strip_edges().to_upper().replace(" ", "")


static func is_room_code(value: String) -> bool:
	var normalized := normalize_room_code(value)
	if not normalized.begins_with(ROOM_PREFIX) or normalized.length() != 10:
		return false
	for character: String in normalized.trim_prefix(ROOM_PREFIX):
		if not character in "23456789ABCDEFGHJKLMNPQRSTUVWXYZ":
			return false
	return true
