-- Public clients must be able to discover a public WebSocket server before
-- creating an account. These grants are SELECT-only; all server registration,
-- heartbeat, match, ticket, profile, and moderation writes remain protected.

grant select on public.service_regions, public.match_servers to anon;

insert into public.service_regions (
  region_key,
  display_name,
  lifecycle,
  status_message,
  sort_order
) values (
  'us-east',
  'US East',
  'operational',
  '',
  10
)
on conflict (region_key) do nothing;

drop policy if exists "public reads healthy service regions"
on public.service_regions;
create policy "public reads healthy service regions"
on public.service_regions for select to anon
using (lifecycle in ('operational', 'degraded'));

drop policy if exists "public discovers joinable match servers"
on public.match_servers;
create policy "public discovers joinable match servers"
on public.match_servers for select to anon
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
