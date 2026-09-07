extends SceneTree

const Factory := preload("res://scripts/network/socom_transport_factory.gd")
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var map := MapDocument.load_path("res://config/maps/relic_depot.json")
	var payload := var_to_bytes(map)
	_check(not map.is_empty(), "canonical deployment map loads")
	_check(payload.size() > 65535, "regression exercises a payload larger than engine defaults")
	var port := 16442
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
	var hosted := Factory.host("websocket", port, 32)
	if int(hosted.error) != OK:
		_check(false, "test server binds: " + String(hosted.message))
		_finish(payload.size())
		return
	var server: WebSocketMultiplayerPeer = hosted.peer
	var connected := Factory.connect_websocket("ws://127.0.0.1:%d" % port, port, false)
	var client: WebSocketMultiplayerPeer = connected.peer
	_check(int(connected.error) == OK, "client created")
	_check(server.outbound_buffer_size > payload.size() * 2, "bounded server buffer has admission headroom")
	_check(client.inbound_buffer_size == server.inbound_buffer_size, "both endpoints share capacity")
	var admitted: Array[int] = []
	server.peer_connected.connect(func(id: int): admitted.append(id))
	var deadline := Time.get_ticks_msec() + 10000
	while (admitted.is_empty() or client.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED) and Time.get_ticks_msec() < deadline:
		server.poll()
		client.poll()
		await process_frame
	_check(not admitted.is_empty(), "client connects")
	if not admitted.is_empty():
		server.set_target_peer(admitted[0])
		_check(server.put_packet(payload) == OK, "server queues entire map without ERR_OUT_OF_MEMORY")
		while client.get_available_packet_count() == 0 and Time.get_ticks_msec() < deadline:
			server.poll()
			client.poll()
			await process_frame
		_check(client.get_available_packet_count() > 0, "client receives map")
		if client.get_available_packet_count() > 0:
			var received := client.get_packet()
			_check(received == payload, "map payload arrives byte-for-byte")
			_check(bytes_to_var(received) == map, "received map matches canonical map")
	client.close()
	server.close()
	_finish(payload.size())

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _finish(byte_count: int) -> void:
	print("NETWORK_MAP_TRANSPORT %s map_bytes=%d %s" % ["PASS" if failures.is_empty() else "FAIL", byte_count, failures])
	quit(0 if failures.is_empty() else 1)
