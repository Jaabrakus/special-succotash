extends "res://scripts/network/socom_multiplayer_directory_presence.gd"

## WebRTC transport adapter for native-private compatibility and automatic
## browser tournament rooms. It installs one MultiplayerPeer only; the
## canonical session and peer 1 retain all lobby and gameplay authority.

const WebRTCSignalingClientScript := preload(
	"res://scripts/network/socom_webrtc_signaling_client.gd"
)

var webrtc_signaling_client = null


func host_webrtc_match(signaling_url: String) -> Error:
	_disconnect_existing_peer()
	return _start_webrtc_signaling(signaling_url, "", true)


func join_webrtc_match(room_code: String, signaling_url: String) -> Error:
	_disconnect_existing_peer()
	if not DeploymentProfile.is_webrtc_room_code(room_code):
		_set_status("JOIN FAILED: Enter a valid P2P room code.")
		return ERR_INVALID_PARAMETER
	return _start_webrtc_signaling(signaling_url, room_code, false, false)


func join_webrtc_tournament(signaling_url: String) -> Error:
	_disconnect_existing_peer()
	return _start_webrtc_signaling(signaling_url, "", false, true)


func _start_webrtc_signaling(
	signaling_url: String,
	room_code: String,
	hosting: bool,
	tournament: bool = false
) -> Error:
	if signaling_url.strip_edges().is_empty():
		_set_status("WEBRTC FAILED: signaling service URL is not configured")
		return ERR_UNCONFIGURED
	webrtc_signaling_client = WebRTCSignalingClientScript.new()
	webrtc_signaling_client.name = "WebRTCSignalingClient"
	webrtc_signaling_client.multiplayer_peer_ready.connect(
		_on_webrtc_multiplayer_peer_ready
	)
	webrtc_signaling_client.failed.connect(_on_webrtc_signaling_failed)
	webrtc_signaling_client.signaling_lost.connect(_on_webrtc_signaling_lost)
	add_child(webrtc_signaling_client)
	var ice_servers := DeploymentProfile.webrtc_ice_servers(
		multiplayer_deployment_profile
	)
	var error: Error
	if tournament:
		error = webrtc_signaling_client.start_tournament(signaling_url, ice_servers)
	elif hosting:
		error = webrtc_signaling_client.start_host(signaling_url, ice_servers)
	else:
		error = webrtc_signaling_client.start_client(signaling_url, room_code, ice_servers)
	if error != OK:
		webrtc_signaling_client.queue_free()
		webrtc_signaling_client = null
		_set_status("WEBRTC FAILED: %s" % error_string(error))
		return error
	active_network_transport = "webrtc_signaling"
	active_network_endpoint = signaling_url
	_set_status(
		"JOINING 32-PLAYER WEBRTC TOURNAMENT…"
		if tournament
		else "CREATING PRIVATE WEBRTC ROOM…"
		if hosting
		else "JOINING WEBRTC ROOM %s…" % room_code.to_upper()
	)
	return OK


func _on_webrtc_multiplayer_peer_ready(
	peer: WebRTCMultiplayerPeer,
	room_code: String,
	hosting: bool,
	tournament: bool
) -> void:
	network_peer = peer
	multiplayer.multiplayer_peer = network_peer
	active_network_transport = DeploymentProfile.TRANSPORT_WEBRTC
	active_network_endpoint = room_code
	if not hosting:
		_set_status("NEGOTIATING WEBRTC ROOM %s…" % room_code)
		return
	lobby.reset()
	lobby.add_player(MultiplayerPeer.TARGET_PEER_SERVER, "HOST")
	_configure_webrtc_host_lobby(tournament)
	session_active = false
	round_active = false
	menu_panel.visible = false
	_show_lobby(true)
	if not tournament:
		multiplayer_hud.show_webrtc_room(room_code)
	_set_status(
		"WEBRTC TOURNAMENT HOST  •  waiting for 16 duos"
		if tournament
		else "HOSTING WEBRTC %s  •  choose a side and green up" % room_code
	)
	_broadcast_lobby()
	print("MP_SLICE HOST_READY transport=webrtc room=%s peer=1" % room_code)


func _configure_webrtc_host_lobby(_tournament: bool) -> void:
	pass


func _on_webrtc_signaling_failed(message: String) -> void:
	_set_status("WEBRTC FAILED: %s" % message)
	if multiplayer.multiplayer_peer == null or active_network_transport == "webrtc_signaling":
		menu_panel.visible = true


func _on_webrtc_signaling_lost(message: String) -> void:
	push_warning(message)
	if active_network_transport == DeploymentProfile.TRANSPORT_WEBRTC:
		_set_status("WEBRTC ACTIVE  •  signaling unavailable; no new players can join")

