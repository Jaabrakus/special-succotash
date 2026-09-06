-- READ ONLY. Run after the migration on the intended Supabase project.
-- Every boolean below should be true. This does not test a real match submission.
select
  not has_column_privilege('authenticated', 'public.player_profiles', 'elo_rating', 'UPDATE') as elo_update_blocked,
  not has_column_privilege('authenticated', 'public.player_profiles', 'elo_rating', 'INSERT') as elo_insert_blocked,
  has_column_privilege('authenticated', 'public.player_profiles', 'display_name', 'UPDATE') as name_edit_allowed,
  not has_table_privilege('anon', 'public.gunfight_tournament_matches', 'INSERT') as anon_results_blocked,
  not has_table_privilege('authenticated', 'public.gunfight_tournament_matches', 'INSERT') as player_results_blocked,
  not has_table_privilege('authenticated', 'public.tournament_event_inbox', 'INSERT') as inbox_insert_blocked,
  not has_table_privilege('anon', 'public.gunfight_leaderboard', 'SELECT') as raw_leaderboard_private,
  not has_function_privilege('authenticated', 'public.server_record_tournament_event(text,text,integer,text,jsonb)', 'EXECUTE') as result_rpc_player_blocked,
  not has_function_privilege('anon', 'public.server_record_tournament_event(text,text,integer,text,jsonb)', 'EXECUTE') as result_rpc_anon_blocked,
  has_function_privilege('service_role', 'public.server_record_tournament_event(text,text,integer,text,jsonb)', 'EXECUTE') as trusted_result_rpc_allowed,
  has_function_privilege('anon', 'public.get_public_gunfight_leaderboard(integer)', 'EXECUTE') as public_leaderboard_allowed;

select relname, relrowsecurity from pg_class
where oid in ('public.player_profiles'::regclass,
  'public.gunfight_tournament_matches'::regclass, 'public.tournament_event_inbox'::regclass);
select policyname, permissive, roles, cmd, qual, with_check from pg_policies
where schemaname = 'public' and tablename = 'player_profiles';
