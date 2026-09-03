extends SceneTree

const Outbox := preload("res://scripts/server/socom_tournament_event_outbox.gd")


func _initialize() -> void:
	var match_id := "outbox_regression_%d" % Time.get_ticks_usec()
	var storage_root := "user://outbox_regression"
	var outbox := Outbox.new()
	assert(outbox.start_session(match_id, storage_root), "outbox starts with a durable journal")
	var event := {
		"event_id": "%s:ROUND_OF_16:arena_0:match_complete" % match_id,
		"match_id": match_id,
		"arena_id": 0,
		"event_type": "ARENA_MATCH_COMPLETED",
		"payload": {"stage": "ROUND_OF_16", "winner_pair_id": 1, "score_alpha": 3, "score_bravo": 1},
		"queued_at_unix": 100.0,
	}
	assert(bool(outbox.enqueue(event).get("accepted", false)), "completed arena event is queued")
	assert(bool(outbox.enqueue(event).get("duplicate", false)), "same event id is idempotent locally")
	assert(outbox.pending_count() == 1, "duplicate queue request does not create another delivery")
	assert(String(outbox.next_pending(100.0).get("event_id", "")) == String(event.event_id), "queued result is ready to deliver")
	assert(outbox.mark_delivery_failed(String(event.event_id), "cloud offline", 100.0), "offline cloud schedules retry")
	assert(outbox.next_pending(101.0).is_empty(), "retry backoff prevents a delivery loop")
	assert(not outbox.next_pending(102.0).is_empty(), "event becomes eligible after bounded retry delay")

	var recovered := Outbox.new()
	assert(recovered.start_session(match_id, storage_root), "outbox reloads after a server restart")
	assert(recovered.pending_count() == 1, "restart retains the undelivered result")
	assert(recovered.mark_delivered(String(event.event_id), 103.0), "cloud acknowledgement is recorded once")
	var acknowledged := Outbox.new()
	assert(acknowledged.start_session(match_id, storage_root), "acknowledged journal reloads")
	assert(acknowledged.pending_count() == 0, "delivered result is never retried")
	print("TOURNAMENT_EVENT_OUTBOX_REGRESSION PASS")
	quit(0)
