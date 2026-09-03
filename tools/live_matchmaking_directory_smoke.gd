extends SceneTree

const MatchmakingDirectoryClient := preload(
	"res://scripts/network/socom_matchmaking_directory_client.gd"
)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var supabase := root.get_node_or_null("SupabaseClient") as SocomSupabaseClient
	if supabase == null or not supabase.is_configured():
		_fail("public Supabase configuration is unavailable")
		return
	var directory := MatchmakingDirectoryClient.new(supabase)
	var region_result: Dictionary = await directory.list_healthy_regions()
	if not bool(region_result.get("ok", false)):
		_fail(String(region_result.get("message", "region request failed")))
		return
	var regions: Array = region_result.get("regions", [])
	var server_count := 0
	for raw_region: Variant in regions:
		if raw_region is not Dictionary:
			continue
		var region_key := String((raw_region as Dictionary).get("region_key", ""))
		var server_result: Dictionary = await directory.list_healthy_servers(region_key)
		if not bool(server_result.get("ok", false)):
			_fail(String(server_result.get("message", "server request failed")))
			return
		server_count += (server_result.get("servers", []) as Array).size()
	print(
		"LIVE_MATCHMAKING_DIRECTORY_SMOKE PASS regions=%d healthy_servers=%d"
		% [regions.size(), server_count]
	)
	quit(0)


func _fail(message: String) -> void:
	push_error("LIVE_MATCHMAKING_DIRECTORY_SMOKE FAIL " + message)
	quit(1)
