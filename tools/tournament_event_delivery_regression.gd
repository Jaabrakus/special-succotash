extends SceneTree

const ServerBackend := preload("res://scripts/server/socom_server_backend.gd")

var request_path := ""
var request_body: Dictionary = {}


func _initialize() -> void:
	var backend := ServerBackend.new()
	backend.project_url = "https://example.supabase.co"
	backend.server_key = "regression-server-secret"
	backend.request_adapter = Callable(self, "_fake_request")
	root.add_child(backend)
	var result: Dictionary = await backend.record_tournament_event({
		"event_id": "match_42:ROUND_OF_16:arena_2:complete",
		"match_id": "match_42",
		"arena_id": 2,
		"event_type": "ARENA_MATCH_COMPLETED",
		"payload": {
			"stage": "ROUND_OF_16",
			"pair_alpha_id": 4,
			"pair_bravo_id": 9,
			"score_alpha": 3,
			"score_bravo": 1,
			"winner_pair_id": 4,
		},
	})
	assert(bool(result.get("ok", false)), "trusted backend accepts a well-formed tournament result")
	assert(request_path == "/rest/v1/rpc/server_record_tournament_event", "delivery uses the idempotent tournament RPC")
	assert(String(request_body.get("target_event_id", "")) == "match_42:ROUND_OF_16:arena_2:complete", "event id is forwarded unchanged")
	assert(int(request_body.get("target_arena_id", -1)) == 2, "arena id is forwarded")
	assert(String(request_body.get("target_event_type", "")) == "ARENA_MATCH_COMPLETED", "event type is forwarded")
	assert(not bool((await backend.record_tournament_event({})).get("ok", false)), "malformed result cannot reach cloud delivery")
	print("TOURNAMENT_EVENT_DELIVERY_REGRESSION PASS")
	quit(0)


func _fake_request(path: String, _method: HTTPClient.Method, body: Variant, _prefer: String) -> Dictionary:
	request_path = path
	request_body = body as Dictionary if body is Dictionary else {}
	return {"ok": true, "status": 200, "data": {"ok": true, "duplicate": false}}
