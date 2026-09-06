-- Apply after the existing game migrations. Transactional and rerunnable.
-- No rows are deleted or ranking values recalculated.
begin;

alter table public.player_profiles enable row level security;
alter table public.gunfight_tournament_matches enable row level security;
alter table public.tournament_event_inbox enable row level security;

-- Table grants include newly added columns: ownership RLS alone does NOT
-- prevent players from editing their own ELO. Remove both table and column ACLs.
revoke all on public.player_profiles, public.gunfight_tournament_matches,
  public.tournament_event_inbox from public, anon, authenticated;
do $$
declare col record;
begin
  for col in
    select table_name, column_name from information_schema.columns
    where table_schema = 'public' and table_name in
      ('player_profiles', 'gunfight_tournament_matches', 'tournament_event_inbox')
  loop
    execute format('revoke all (%I) on public.%I from public, anon, authenticated',
      col.column_name, col.table_name);
  end loop;
end;
$$;

grant select on public.player_profiles to authenticated;
grant insert (user_id, display_name), update (display_name)
  on public.player_profiles to authenticated;
do $$
begin
  -- Support projects with either historical profile schema.
  if exists (select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'player_profiles' and column_name = 'handle') then
    grant insert (handle), update (handle) on public.player_profiles to authenticated;
  end if;
end;
$$;

drop policy if exists "signed in players read profiles" on public.player_profiles;
drop policy if exists "players create their own profile" on public.player_profiles;
drop policy if exists "players update their own profile" on public.player_profiles;
drop policy if exists "ranked profile owner access" on public.player_profiles;
drop policy if exists "ranked profile owner fence" on public.player_profiles;
create policy "ranked profile owner access" on public.player_profiles
  for all to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
-- A restrictive fence also prevents old permissive policies widening access.
create policy "ranked profile owner fence" on public.player_profiles as restrictive
  for all to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

grant all on public.player_profiles, public.gunfight_tournament_matches,
  public.tournament_event_inbox to service_role;

-- Keep the curated public RPC; do not expose the old owner-executed raw view.
revoke all on public.gunfight_leaderboard from public, anon, authenticated;
revoke all on function public.server_record_tournament_event(text, text, integer, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.server_record_tournament_event(text, text, integer, text, jsonb)
  to service_role;
alter function public.server_record_tournament_event(text, text, integer, text, jsonb)
  set search_path = pg_catalog, pg_temp;
alter function public.get_public_gunfight_leaderboard(integer)
  set search_path = pg_catalog, pg_temp;
revoke all on function public.get_public_gunfight_leaderboard(integer) from public;
grant execute on function public.get_public_gunfight_leaderboard(integer) to anon, authenticated;

commit;
