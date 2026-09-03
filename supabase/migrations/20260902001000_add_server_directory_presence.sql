-- Browser-safe dedicated-server presence metadata.
-- The service-role game server is the only writer. Authenticated clients retain
-- their existing read-only access to healthy match_servers rows.

alter table public.match_servers
  add column mode_key text not null default 'demolition'
    check (mode_key ~ '^[a-z0-9][a-z0-9_-]{0,39}$'),
  add column map_key text not null default 'unknown'
    check (map_key ~ '^[a-z0-9][a-z0-9_-]{0,63}$'),
  add column session_stage text not null default 'lobby'
    check (session_stage in (
      'lobby', 'countdown', 'active', 'round_of_16', 'quarterfinals',
      'semifinals', 'grand_finals', 'complete'
    )),
  add column free_arenas smallint not null default 1
    check (free_arenas between 0 and 8);

create index match_servers_browser_directory_idx
on public.match_servers (
  status,
  accepting_players,
  region,
  mode_key,
  session_stage,
  current_players,
  last_heartbeat_at desc
);
