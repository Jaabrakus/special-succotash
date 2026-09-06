extends SceneTree
const Factory = preload("res://scripts/network/socom_transport_factory.gd")
var peer: WebSocketMultiplayerPeer
var client := false
var sent := false
var deadline: int
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	client = args.has("--client")
	var port := int(args[-1])
	deadline = Time.get_ticks_msec() + 15000
	if client:
		var result := Factory.connect_websocket("ws://127.0.0.1:%d" % port, port, false)
		assert(result.error == OK)
		peer = result.peer
	else:
		var result := Factory.host("websocket", port, 32)
		assert(result.error == OK)
		peer = result.peer
		print("GATEWAY_BACKEND_READY")
func _process(_delta: float) -> bool:
	peer.poll()
	if Time.get_ticks_msec() > deadline:
		quit(2)
	if client and not sent and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		peer.set_target_peer(1)
		peer.put_packet("gateway-roundtrip".to_utf8_buffer())
		sent = true
	while peer.get_available_packet_count() > 0:
		var sender := peer.get_packet_peer()
		var packet := peer.get_packet()
		if client:
			assert(packet.get_string_from_utf8() == "gateway-roundtrip")
			print("GATEWAY_GODOT_ROUNDTRIP_PASS")
			peer.close()
			quit()
		else:
			peer.set_target_peer(sender)
			peer.put_packet(packet)
	return false
