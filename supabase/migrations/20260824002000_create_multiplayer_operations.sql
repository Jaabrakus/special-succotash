-- SOCOM-141 multiplayer operations, service health, moderation, and abuse controls.
-- Client roles can create only self-owned social/moderation records. Match-server
-- health, sanctions, evidence, audit records, and match authority stay service-only.

alter table public.match_servers
  add column protocol_version integer not null default 1 check (protocol_version > 0),
  add column accepting_players boolean not null default true,
  add column current_players smallint not null default 0 check (current_players between 0 and 16),
  add column tick_rate_hz numeric(7,3) check (tick_rate_hz is null or tick_rate_hz between 0 and 240),
  add column cpu_percent numeric(6,3) check (cpu_percent is null or cpu_percent between 0 and 100),
  add column memory_mb numeric(10,3) check (memory_mb is null or memory_mb between 0 and 1048576),
  add column outbound_kbps numeric(12,3) check (outbound_kbps is null or outbound_kbps >= 0),
  add constraint match_servers_current_capacity_check check (current_players <= capacity);

create table public.service_regions (
  region_key text primary key check (region_key ~ '^[a-z0-9-]{2,32}$'),
  display_name text not null check (char_length(display_name) between 2 and 64),
  lifecycle text not null default 'operational'
    check (lifecycle in ('operational', 'degraded', 'maintenance', 'offline')),
  status_message text not null default '' check (char_length(status_message) <= 240),
  sort_order smallint not null default 100,
  last_probe_at timestamptz,
  updated_at timestamptz not null default now()
);

create table public.player_blocks (
  blocker_user_id uuid not null references auth.users(id) on delete cascade,
  blocked_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_user_id, blocked_user_id),
  check (blocker_user_id <> blocked_user_id)
);

create table public.player_mutes (
  muting_user_id uuid not null references auth.users(id) on delete cascade,
  muted_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (muting_user_id, muted_user_id),
  check (muting_user_id <> muted_user_id)
);

create table public.moderation_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_user_id uuid not null references auth.users(id) on delete restrict,
  reported_user_id uuid references auth.users(id) on delete set null,
  match_id uuid references public.matches(id) on delete set null,
  category text not null check (category in (
    'cheating', 'harassment', 'hate', 'threat', 'griefing', 'voice', 'name', 'other'
  )),
  summary text not null check (char_length(summary) between 1 and 1000),
  evidence_window_start timestamptz,
  evidence_window_end timestamptz,
  status text not null default 'submitted'
    check (status in ('submitted', 'triaged', 'investigating', 'actioned', 'dismissed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (reported_user_id is null or reporter_user_id <> reported_user_id),
  check (
    evidence_window_start is null or evidence_window_end is null
    or evidence_window_end >= evidence_window_start
  )
);

create index moderation_reports_subject_idx
on public.moderation_reports (reported_user_id, created_at desc);

create table public.moderation_evidence (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.moderation_reports(id) on delete cascade,
  storage_path text not null check (char_length(storage_path) between 1 and 512),
  content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  content_type text not null check (char_length(content_type) between 1 and 100),
  size_bytes bigint not null check (size_bytes between 1 and 52428800),
  retention_until timestamptz not null,
  captured_by_server_id uuid references public.match_servers(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.moderation_actions (
  id uuid primary key default gen_random_uuid(),
  target_user_id uuid not null references auth.users(id) on delete restrict,
  action_type text not null
    check (action_type in ('warning', 'kick', 'temporary_ban', 'permanent_ban', 'voice_ban')),
  reason_code text not null check (reason_code ~ '^[a-z0-9_]{2,40}$'),
  public_reason text not null check (char_length(public_reason) between 1 and 500),
  source_report_id uuid references public.moderation_reports(id) on delete set null,
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  revoked_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (expires_at is null or expires_at > starts_at)
);

create index moderation_actions_active_target_idx
on public.moderation_actions (target_user_id, starts_at desc)
where revoked_at is null;

create table public.moderation_appeals (
  id uuid primary key default gen_random_uuid(),
  action_id uuid not null references public.moderation_actions(id) on delete restrict,
  appellant_user_id uuid not null references auth.users(id) on delete restrict,
  statement text not null check (char_length(statement) between 20 and 2000),
  status text not null default 'submitted'
    check (status in ('submitted', 'reviewing', 'upheld', 'modified', 'overturned')),
  resolution text not null default '' check (char_length(resolution) <= 1000),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  unique (action_id, appellant_user_id)
);

create table public.security_audit_log (
  id bigint generated always as identity primary key,
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_kind text not null check (actor_kind in ('player', 'moderator', 'server', 'system')),
  action text not null check (action ~ '^[a-z0-9_.-]{2,80}$'),
  target_type text not null default '' check (char_length(target_type) <= 40),
  target_id text not null default '' check (char_length(target_id) <= 128),
  request_id uuid not null default gen_random_uuid(),
  ip_hash text check (ip_hash is null or ip_hash ~ '^[0-9a-f]{64}$'),
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default now()
);

create or replace function public.record_moderation_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  record_id text := coalesce(new.id::text, '');
begin
  insert into public.security_audit_log (
    actor_user_id, actor_kind, action, target_type, target_id, details
  ) values (
    auth.uid(),
    case when auth.uid() is null then 'server' else 'player' end,
    'moderation.' || tg_table_name || '.' || lower(tg_op),
    tg_table_name,
    record_id,
    jsonb_build_object('status', coalesce(to_jsonb(new) ->> 'status', ''))
  );
  return new;
end;
$$;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table private.api_rate_limits (
  principal_user_id uuid not null references auth.users(id) on delete cascade,
  route_key text not null check (route_key ~ '^[a-z0-9_.-]{2,80}$'),
  window_started_at timestamptz not null,
  request_count integer not null check (request_count > 0),
  primary key (principal_user_id, route_key)
);

create or replace function public.consume_api_rate_limit(
  requested_route text,
  maximum_requests integer default 30,
  window_seconds integer default 60
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  principal uuid := auth.uid();
  current_count integer;
begin
  if principal is null
    or requested_route !~ '^[a-z0-9_.-]{2,80}$'
    or maximum_requests < 1 or maximum_requests > 600
    or window_seconds < 1 or window_seconds > 3600 then
    return false;
  end if;

  insert into private.api_rate_limits (
    principal_user_id, route_key, window_started_at, request_count
  ) values (
    principal, requested_route, now(), 1
  )
  on conflict (principal_user_id, route_key) do update
  set
    window_started_at = case
      when private.api_rate_limits.window_started_at <= now() - make_interval(secs => window_seconds)
      then now() else private.api_rate_limits.window_started_at end,
    request_count = case
      when private.api_rate_limits.window_started_at <= now() - make_interval(secs => window_seconds)
      then 1 else private.api_rate_limits.request_count + 1 end
  returning request_count into current_count;

  return current_count <= maximum_requests;
end;
$$;

alter table public.service_regions enable row level security;
alter table public.player_blocks enable row level security;
alter table public.player_mutes enable row level security;
alter table public.moderation_reports enable row level security;
alter table public.moderation_evidence enable row level security;
alter table public.moderation_actions enable row level security;
alter table public.moderation_appeals enable row level security;
alter table public.security_audit_log enable row level security;

revoke all on public.service_regions, public.player_blocks, public.player_mutes,
  public.moderation_reports, public.moderation_evidence, public.moderation_actions,
  public.moderation_appeals, public.security_audit_log from anon, authenticated;

grant select on public.service_regions to authenticated;
grant select, insert, delete on public.player_blocks, public.player_mutes to authenticated;
grant select, insert on public.moderation_reports, public.moderation_appeals to authenticated;
grant select on public.moderation_actions to authenticated;
grant all on public.service_regions, public.player_blocks, public.player_mutes,
  public.moderation_reports, public.moderation_evidence, public.moderation_actions,
  public.moderation_appeals, public.security_audit_log to service_role;
grant usage, select on sequence public.security_audit_log_id_seq to service_role;

revoke all on function public.consume_api_rate_limit(text, integer, integer) from public, anon;
grant execute on function public.consume_api_rate_limit(text, integer, integer) to authenticated;
revoke all on function public.record_moderation_audit() from public, anon, authenticated;

create policy "players read service health"
on public.service_regions for select to authenticated
using (true);

create policy "players manage their block list"
on public.player_blocks for all to authenticated
using (blocker_user_id = (select auth.uid()))
with check (blocker_user_id = (select auth.uid()));

create policy "players manage their mute list"
on public.player_mutes for all to authenticated
using (muting_user_id = (select auth.uid()))
with check (muting_user_id = (select auth.uid()));

create policy "players submit their reports"
on public.moderation_reports for insert to authenticated
with check (reporter_user_id = (select auth.uid()) and status = 'submitted');

create policy "players read their reports"
on public.moderation_reports for select to authenticated
using (reporter_user_id = (select auth.uid()));

create policy "players read sanctions against them"
on public.moderation_actions for select to authenticated
using (target_user_id = (select auth.uid()));

create policy "players submit appeals for their sanctions"
on public.moderation_appeals for insert to authenticated
with check (
  appellant_user_id = (select auth.uid())
  and status = 'submitted'
  and exists (
    select 1 from public.moderation_actions action
    where action.id = action_id and action.target_user_id = (select auth.uid())
  )
);

create policy "players read their appeals"
on public.moderation_appeals for select to authenticated
using (appellant_user_id = (select auth.uid()));

drop policy if exists "players discover online match servers" on public.match_servers;
create policy "players discover compatible healthy match servers"
on public.match_servers for select to authenticated
using (
  status = 'online'
  and accepting_players
  and current_players < capacity
  and last_heartbeat_at > now() - interval '45 seconds'
  and exists (
    select 1 from public.service_regions region_status
    where region_status.region_key = region
      and region_status.lifecycle in ('operational', 'degraded')
  )
);

create trigger moderation_reports_set_updated_at
before update on public.moderation_reports
for each row execute function public.set_game_service_updated_at();

create trigger moderation_reports_audit
after insert or update on public.moderation_reports
for each row execute function public.record_moderation_audit();

create trigger moderation_actions_audit
after insert or update on public.moderation_actions
for each row execute function public.record_moderation_audit();

create trigger moderation_appeals_audit
after insert or update on public.moderation_appeals
for each row execute function public.record_moderation_audit();
