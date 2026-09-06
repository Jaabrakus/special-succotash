extends SceneTree

const DeploymentProfile := preload(
	"res://scripts/network/socom_multiplayer_deployment_profile.gd"
)
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MapGameplay := preload("res://scripts/maps/socom_map_gameplay_contract.gd")
const CAPACITY_MIGRATION_PATH := (
	"res://supabase/migrations/20260902000000_expand_multiarena_server_capacity.sql"
)

var failures: Array[String] = []


func _initialize() -> void:
	var profile := DeploymentProfile.load_profile()
	_expect(int(profile.get("max_players", 0)) == 32, "deployment admits 32 players")
	_expect(
		String(profile.get("browser_transport", "")) == DeploymentProfile.TRANSPORT_WEBRTC
		and String(profile.get("browser_tournament_transport", "")) == DeploymentProfile.TRANSPORT_WEBRTC,
		"browser tournament uses WebRTC for its canonical transport"
	)
	_expect(int(profile.get("arena_instances", 0)) == 8, "deployment owns eight arena instances")
	_expect(int(profile.get("players_per_arena", 0)) == 4, "each arena owns one 2v2 match")
	_expect(
		String(profile.get("server_map_document", ""))
		== "res://config/maps/painterly_coastal_village_2v2.json",
		"dedicated launch selects the bundled stair-playable 2v2 map"
	)
	var deployment_map := MapDocument.load_path(String(profile.get("server_map_document", "")))
	var deployment_layout := MapGameplay.demolition_layout(deployment_map)
	var stair_count := 0
	for raw_object: Variant in deployment_map.get("objects", []):
		if raw_object is Dictionary and String((raw_object as Dictionary).get("type", "")) == "stairs":
			stair_count += 1
	_expect(stair_count > 0, "dedicated map contains authored traversable stairs")
	_expect(
		(deployment_layout.get("alpha_spawns", []) as Array).size() >= 2
		and (deployment_layout.get("bravo_spawns", []) as Array).size() >= 2,
		"dedicated map contains all four authored 2v2 starts"
	)
	_expect(
		DeploymentProfile.requested_server_transport(PackedStringArray(), true, profile)
		== DeploymentProfile.TRANSPORT_WEBSOCKET,
		"dedicated server defaults to browser-compatible WebSocket transport"
	)
	_expect(
		DeploymentProfile.requested_server_transport(PackedStringArray(), false, profile)
		== DeploymentProfile.TRANSPORT_ENET,
		"native listen-server behavior remains ENet"
	)
	_expect(
		DeploymentProfile.requested_client_transport("127.0.0.1", PackedStringArray(), true)
		== DeploymentProfile.TRANSPORT_WEBSOCKET,
		"browser clients cannot select unsupported ENet transport"
	)
	_expect(
		DeploymentProfile.requested_client_transport("ws://127.0.0.1:14141", PackedStringArray(), false)
		== DeploymentProfile.TRANSPORT_WEBSOCKET,
		"native clients can exercise the same WebSocket protocol"
	)
	var public_endpoint := DeploymentProfile.websocket_endpoint(
		"wss://play.example.test/socom",
		14141,
		true
	)
	_expect(
		bool(public_endpoint.get("ok", false))
		and String(public_endpoint.get("url", "")) == "wss://play.example.test/socom",
		"secure public WebSocket paths survive normalization"
	)
	var insecure_browser_endpoint := DeploymentProfile.websocket_endpoint(
		"ws://play.example.test:14141",
		14141,
		true
	)
	_expect(
		not bool(insecure_browser_endpoint.get("ok", true)),
		"browser deployment rejects mixed-content ws:// endpoints"
	)
	var native_endpoint := DeploymentProfile.websocket_endpoint(
		"127.0.0.1:14141",
		14141,
		false
	)
	_expect(
		bool(native_endpoint.get("ok", false))
		and String(native_endpoint.get("url", "")) == "ws://127.0.0.1:14141",
		"local native WebSocket proof accepts an unencrypted loopback endpoint"
	)
	_expect(
		String(ProjectSettings.get_setting("application/run/main_scene", ""))
		== "res://game_launcher.tscn",
		"the canonical application boots through the playable launcher"
	)
	var capacity_migration := FileAccess.get_file_as_string(CAPACITY_MIGRATION_PATH)
	_expect(
		capacity_migration.contains("check (capacity between 2 and 32)")
		and capacity_migration.contains("check (current_players between 0 and 32)"),
		"server discovery schema accepts the same 32-player ceiling"
	)
	var admission_source := FileAccess.get_file_as_string(
		"res://scripts/network/socom_multiplayer_admission.gd"
	)
	_expect(
		admission_source.contains("lobby.players.size() >= MAX_PLAYERS")
		and admission_source.contains("this 32-player server is full"),
		"admission rejects overflow before adding a thirty-third player"
	)
	if failures.is_empty():
		print("BROWSER_MULTI_ARENA_DEPLOYMENT_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("BROWSER_MULTI_ARENA_DEPLOYMENT_REGRESSION: %s" % failure)
	quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("BROWSER_MULTI_ARENA_CHECK PASS ", label)
	else:
		failures.append(label)
