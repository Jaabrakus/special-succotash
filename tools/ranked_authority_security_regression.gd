extends SceneTree

func _initialize() -> void:
	var sql := FileAccess.get_file_as_string("res://supabase/migrations/20260906010000_lock_ranked_result_authority.sql")
	assert(sql.contains("begin;") and sql.contains("commit;"))
	assert(sql.contains("grant insert (user_id, display_name), update (display_name)"))
	assert(sql.contains("revoke all (%I)"))
	assert(sql.contains("as restrictive"))
	for table in ["player_profiles", "gunfight_tournament_matches", "tournament_event_inbox"]:
		assert(sql.contains("alter table public.%s enable row level security;" % table))
	assert(sql.contains("from public, anon, authenticated"))
	assert(sql.contains("set search_path = pg_catalog, pg_temp"))
	var delivery := FileAccess.get_file_as_string("res://scripts/network/socom_multiplayer_tournament_runtime.gd")
	assert(delivery.contains("not dedicated_server_mode\n\t\tor tournament_outbox == null"))
	var backend := FileAccess.get_file_as_string("res://scripts/server/socom_server_backend.gd")
	assert(backend.contains('return not OS.has_feature("web")'))
	print("RANKED_AUTHORITY_SECURITY static contract PASS; SQL execution still requires a database")
	quit()
