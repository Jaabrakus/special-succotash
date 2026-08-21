-- SOCOM-141 account, matchmaking, dedicated-server, and match-result schema.
--
-- Authority boundary:
--   * Supabase stores identity, approved rulesets, loadouts, discovery, and results.
--   * The dedicated Godot server owns live movement, shots, ammo, damage, rounds,
--     and demolition state. Clients cannot write authoritative match results.

create extension if not exists pgcrypto;

create table public.player_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  handle text not null check (handle ~ '^[A-Za-z0-9_]{3,20}$'),
  display_name text not null default '' check (char_length(display_name) <= 40),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index player_profiles_handle_ci_idx on public.player_profiles (lower(handle));

create table public.gameplay_rulesets (
  id uuid primary key default gen_random_uuid(),
  ruleset_key text not null check (ruleset_key ~ '^[a-z0-9_]{2,40}$'),
  version integer not null check (version > 0),
  game_build text not null check (char_length(game_build) between 1 and 80),
  lifecycle text not null default 'draft' check (lifecycle in ('draft', 'active', 'retired')),
  weapon_manifest jsonb not null default '{}'::jsonb check (jsonb_typeof(weapon_manifest) = 'object'),
  movement_manifest jsonb not null default '{}'::jsonb check (jsonb_typeof(movement_manifest) = 'object'),
  mode_manifest jsonb not null default '{}'::jsonb check (jsonb_typeof(mode_manifest) = 'object'),
  content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  activated_at timestamptz,
  unique (ruleset_key, version)
);

create unique index gameplay_rulesets_one_active_idx
on public.gameplay_rulesets (ruleset_key)
where lifecycle = 'active';

create table public.player_loadouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  slot smallint not null check (slot between 1 and 10),
  name text not null default 'Loadout' check (char_length(name) between 1 and 40),
  ruleset_id uuid references public.gameplay_rulesets(id) on delete restrict,
  primary_weapon_id text not null check (char_length(primary_weapon_id) between 1 and 64),
  secondary_weapon_id text check (secondary_weapon_id is null or char_length(secondary_weapon_id) between 1 and 64),
  equipment jsonb not null default '[]'::jsonb check (jsonb_typeof(equipment) = 'array'),
  updated_at timestamptz not null default now(),
  unique (user_id, slot)
);

create table public.match_servers (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  region text not null check (region ~ '^[a-z0-9-]{2,32}$'),
  public_address text not null check (char_length(public_address) between 1 and 255),
  public_port integer not null check (public_port between 1 and 65535),
  game_build text not null check (char_length(game_build) between 1 and 80),
  ruleset_id uuid not null references public.gameplay_rulesets(id) on delete restrict,
  capacity smallint not null default 16 check (capacity between 2 and 16),
  status text not null default 'offline' check (status in ('offline', 'online', 'draining')),
  last_heartbeat_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (public_address, public_port)
);

create index match_servers_discovery_idx
on public.match_servers (status, region, last_heartbeat_at desc);

create table public.matches (
  id uuid primary key default gen_random_uuid(),
  server_id uuid not null references public.match_servers(id) on delete restrict,
  ruleset_id uuid not null references public.gameplay_rulesets(id) on delete restrict,
  community_map_version_id uuid references public.community_map_versions(id) on delete restrict,
  official_map_key text,
  mode text not null check (mode in ('demolition', 'team_deathmatch')),
  status text not null default 'lobby' check (status in ('lobby', 'active', 'completed', 'cancelled')),
  max_players smallint not null default 16 check (max_players between 2 and 16),
  winning_team smallint check (winning_team is null or winning_team in (0, 1)),
  completion_reason text,
  result_summary jsonb not null default '{}'::jsonb check (jsonb_typeof(result_summary) = 'object'),
  created_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  check (community_map_version_id is not null or official_map_key is not null)
);

create index matches_server_status_idx on public.matches (server_id, status, created_at desc);
create index matches_status_created_idx on public.matches (status, created_at desc);

create table public.match_players (
  match_id uuid not null references public.matches(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete restrict,
  team smallint not null check (team in (0, 1)),
  loadout_snapshot jsonb not null default '{}'::jsonb check (jsonb_typeof(loadout_snapshot) = 'object'),
  kills integer not null default 0 check (kills >= 0),
  deaths integer not null default 0 check (deaths >= 0),
  assists integer not null default 0 check (assists >= 0),
  objective_score integer not null default 0 check (objective_score >= 0),
  median_rtt_ms numeric(8,3) check (median_rtt_ms is null or median_rtt_ms between 0 and 5000),
  jitter_ms numeric(8,3) check (jitter_ms is null or jitter_ms between 0 and 5000),
  packet_loss_percent numeric(6,3) check (packet_loss_percent is null or packet_loss_percent between 0 and 100),
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  primary key (match_id, user_id)
);

create index match_players_user_idx on public.match_players (user_id, joined_at desc);

create table public.match_rounds (
  match_id uuid not null references public.matches(id) on delete cascade,
  round_number smallint not null check (round_number between 1 and 25),
  winning_team smallint check (winning_team is null or winning_team in (0, 1)),
  resolution text not null check (resolution in ('elimination', 'bomb_detonated', 'bomb_defused', 'timeout', 'forfeit', 'cancelled')),
  duration_seconds numeric(8,3) not null check (duration_seconds >= 0),
  summary jsonb not null default '{}'::jsonb check (jsonb_typeof(summary) = 'object'),
  completed_at timestamptz not null default now(),
  primary key (match_id, round_number)
);

create table public.matchmaking_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  mode text not null check (mode in ('demolition', 'team_deathmatch')),
  preferred_region text not null default 'auto' check (preferred_region ~ '^[a-z0-9-]{2,32}$'),
  party_id uuid,
  status text not null default 'queued' check (status in ('queued', 'matched', 'cancelled', 'expired')),
  matched_match_id uuid references public.matches(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '10 minutes'),
  check (
    (status = 'matched' and matched_match_id is not null)
    or (status <> 'matched')
  )
);

create unique index matchmaking_one_live_ticket_idx
on public.matchmaking_tickets (user_id)
where status = 'queued';

create index matchmaking_queue_idx
on public.matchmaking_tickets (status, mode, preferred_region, created_at);

create or replace function public.set_game_service_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger player_profiles_set_updated_at
before update on public.player_profiles
for each row execute function public.set_game_service_updated_at();

create trigger player_loadouts_set_updated_at
before update on public.player_loadouts
for each row execute function public.set_game_service_updated_at();

create trigger match_servers_set_updated_at
before update on public.match_servers
for each row execute function public.set_game_service_updated_at();

create or replace function public.create_player_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.player_profiles (user_id, handle, display_name)
  values (
    new.id,
    'player_' || left(replace(new.id::text, '-', ''), 8),
    coalesce(left(new.raw_user_meta_data ->> 'display_name', 40), '')
  );
  return new;
end;
$$;

create trigger auth_user_created_create_player_profile
after insert on auth.users
for each row execute function public.create_player_profile_for_new_user();

create or replace function public.is_match_participant(target_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.match_players mp
    where mp.match_id = target_match_id
      and mp.user_id = auth.uid()
  );
$$;

revoke all on function public.is_match_participant(uuid) from public;
grant execute on function public.is_match_participant(uuid) to authenticated;

alter table public.player_profiles enable row level security;
alter table public.gameplay_rulesets enable row level security;
alter table public.player_loadouts enable row level security;
alter table public.match_servers enable row level security;
alter table public.matches enable row level security;
alter table public.match_players enable row level security;
alter table public.match_rounds enable row level security;
alter table public.matchmaking_tickets enable row level security;

revoke all on public.player_profiles, public.gameplay_rulesets, public.player_loadouts,
  public.match_servers, public.matches, public.match_players, public.match_rounds,
  public.matchmaking_tickets from anon, authenticated;

grant select on public.gameplay_rulesets to anon, authenticated;
grant select, insert, update on public.player_profiles to authenticated;
grant select, insert, update, delete on public.player_loadouts to authenticated;
grant select on public.match_servers, public.matches, public.match_players, public.match_rounds to authenticated;
grant select, insert, update, delete on public.matchmaking_tickets to authenticated;
grant all on public.player_profiles, public.gameplay_rulesets, public.player_loadouts,
  public.match_servers, public.matches, public.match_players, public.match_rounds,
  public.matchmaking_tickets to service_role;

create policy "active gameplay rulesets are readable"
on public.gameplay_rulesets for select to anon, authenticated
using (lifecycle = 'active');

create policy "signed in players read profiles"
on public.player_profiles for select to authenticated
using (true);

create policy "players create their own profile"
on public.player_profiles for insert to authenticated
with check (user_id = (select auth.uid()));

create policy "players update their own profile"
on public.player_profiles for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create policy "players manage their own loadouts"
on public.player_loadouts for all to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create policy "players discover online match servers"
on public.match_servers for select to authenticated
using (status = 'online');

create policy "players discover live or joined matches"
on public.matches for select to authenticated
using (status in ('lobby', 'active') or public.is_match_participant(id));

create policy "match participants read the roster"
on public.match_players for select to authenticated
using (public.is_match_participant(match_id));

create policy "match participants read completed rounds"
on public.match_rounds for select to authenticated
using (public.is_match_participant(match_id));

create policy "players read their own matchmaking tickets"
on public.matchmaking_tickets for select to authenticated
using (user_id = (select auth.uid()));

create policy "players enter matchmaking"
on public.matchmaking_tickets for insert to authenticated
with check (
  user_id = (select auth.uid())
  and status = 'queued'
  and matched_match_id is null
);

create policy "players may only cancel their queued ticket"
on public.matchmaking_tickets for update to authenticated
using (user_id = (select auth.uid()) and status = 'queued')
with check (
  user_id = (select auth.uid())
  and status = 'cancelled'
  and matched_match_id is null
);

create policy "players delete only inactive tickets"
on public.matchmaking_tickets for delete to authenticated
using (user_id = (select auth.uid()) and status in ('cancelled', 'expired'));
