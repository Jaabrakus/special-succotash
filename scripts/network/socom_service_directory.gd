class_name SocomServiceDirectory
extends RefCounted

## Pure selection policy for backend service rows. The UI can display every
## region state, but matchmaking selects only healthy, compatible capacity.

const HEALTHY_REGION_STATES := ["operational", "degraded"]
const SERVER_HEARTBEAT_MAX_AGE_SECONDS := 45.0


static func choose_region(regions: Array, preferred_region: String = "auto") -> Dictionary:
	var candidates: Array[Dictionary] = []
	for raw_region in regions:
		if raw_region is not Dictionary:
			continue
		var region := raw_region as Dictionary
		if String(region.get("lifecycle", "offline")) not in HEALTHY_REGION_STATES:
			continue
		candidates.append(region)
	if candidates.is_empty():
		return {"ok": false, "message": "No multiplayer region is healthy."}
	for region: Dictionary in candidates:
		if preferred_region != "auto" and String(region.get("region_key", "")) == preferred_region:
			return {"ok": true, "region": region}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_latency := float(a.get("measured_latency_ms", INF))
		var b_latency := float(b.get("measured_latency_ms", INF))
		if not is_equal_approx(a_latency, b_latency):
			return a_latency < b_latency
		return int(a.get("sort_order", 100)) < int(b.get("sort_order", 100))
	)
	return {"ok": true, "region": candidates[0]}


static func choose_server(
	servers: Array,
	region_key: String,
	game_build: String,
	protocol_version: int,
	now_unix: float
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for raw_server in servers:
		if raw_server is not Dictionary:
			continue
		var server := raw_server as Dictionary
		if (
			String(server.get("region", "")) != region_key
			or String(server.get("status", "")) != "online"
			or not bool(server.get("accepting_players", false))
			or int(server.get("current_players", 0)) >= int(server.get("capacity", 0))
			or String(server.get("game_build", "")) != game_build
			or int(server.get("protocol_version", 0)) != protocol_version
		):
			continue
		var heartbeat_unix := float(server.get("last_heartbeat_unix", 0.0))
		if heartbeat_unix <= 0.0 or now_unix - heartbeat_unix > SERVER_HEARTBEAT_MAX_AGE_SECONDS:
			continue
		candidates.append(server)
	if candidates.is_empty():
		return {"ok": false, "message": "No compatible server has capacity in this region."}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("current_players", 0)) < int(b.get("current_players", 0))
	)
	return {"ok": true, "server": candidates[0]}
