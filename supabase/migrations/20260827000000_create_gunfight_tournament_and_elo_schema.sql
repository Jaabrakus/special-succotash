-- =============================================================================
-- SOCOM-141 Gunfight 2v2 Tournament, Account Profiles, and ELO Rating Schema
-- Complete Clean Remake with Praetorian 3-2-1 Divisions & Tier K/D Reset
-- =============================================================================

create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- 1. Player Profiles Table (0 ELO, Default Rank: TIRO III)
-- -----------------------------------------------------------------------------
create table if not exists public.player_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  handle text not null default 'Operator',
  display_name text not null default 'Operator',
  elo_rating integer not null default 0 check (elo_rating >= 0),
  rank_tier text not null default 'TIRO III',
  major_tier text not null default 'TIRO',
  tier_kills integer not null default 0 check (tier_kills >= 0),
  tier_deaths integer not null default 0 check (tier_deaths >= 0),
  lifetime_kills integer not null default 0 check (lifetime_kills >= 0),
  lifetime_deaths integer not null default 0 check (lifetime_deaths >= 0),
  tournaments_played integer not null default 0 check (tournaments_played >= 0),
  tournaments_won integer not null default 0 check (tournaments_won >= 0),
  gunfight_matches_won integer not null default 0 check (gunfight_matches_won >= 0),
  gunfight_matches_lost integer not null default 0 check (gunfight_matches_lost >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Backfill / ensure any preexisting table has all new columns
alter table public.player_profiles
  add column if not exists elo_rating integer not null default 0 check (elo_rating >= 0),
  add column if not exists rank_tier text not null default 'TIRO III',
  add column if not exists major_tier text not null default 'TIRO',
  add column if not exists tier_kills integer not null default 0 check (tier_kills >= 0),
  add column if not exists tier_deaths integer not null default 0 check (tier_deaths >= 0),
  add column if not exists lifetime_kills integer not null default 0 check (lifetime_kills >= 0),
  add column if not exists lifetime_deaths integer not null default 0 check (lifetime_deaths >= 0),
  add column if not exists tournaments_played integer not null default 0 check (tournaments_played >= 0),
  add column if not exists tournaments_won integer not null default 0 check (tournaments_won >= 0),
  add column if not exists gunfight_matches_won integer not null default 0 check (gunfight_matches_won >= 0),
  add column if not exists gunfight_matches_lost integer not null default 0 check (gunfight_matches_lost >= 0);

create index if not exists player_profiles_elo_idx on public.player_profiles (elo_rating desc);

-- -----------------------------------------------------------------------------
-- 2. Automatic Profile Generator (Trigger on auth.users)
-- -----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  assigned_name text;
begin
  assigned_name := coalesce(new.raw_user_meta_data->>'display_name', 'Operator_' || substr(new.id::text, 1, 6));
  insert into public.player_profiles (
    user_id, handle, display_name, elo_rating, rank_tier, major_tier,
    tier_kills, tier_deaths, lifetime_kills, lifetime_deaths,
    tournaments_played, tournaments_won, gunfight_matches_won, gunfight_matches_lost
  )
  values (
    new.id, assigned_name, assigned_name, 0, 'TIRO III', 'TIRO',
    0, 0, 0, 0,
    0, 0, 0, 0
  )
  on conflict (user_id) do update set
    display_name = excluded.display_name,
    updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- -----------------------------------------------------------------------------
-- 3. Tournament Matches History Table
-- -----------------------------------------------------------------------------
create table if not exists public.tournament_matches (
  id uuid primary key default gen_random_uuid(),
  tournament_id text not null,
  stage text not null default 'ROUND_OF_16',
  arena_id smallint not null default 0,
  pair_a_id smallint not null default 0,
  pair_b_id smallint not null default 1,
  winner_pair_id smallint,
  score_a smallint not null default 0,
  score_b smallint not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists tournament_matches_tournament_idx on public.tournament_matches (tournament_id, created_at asc);

-- -----------------------------------------------------------------------------
-- 4. Tournament Player Results & ELO Deltas Table
-- -----------------------------------------------------------------------------
create table if not exists public.tournament_player_results (
  id uuid primary key default gen_random_uuid(),
  tournament_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  pair_id smallint not null default 0,
  stage_reached text not null default 'ROUND_OF_16',
  old_elo integer not null default 0,
  new_elo integer not null default 0,
  elo_delta integer not null default 0,
  rank_tier text not null default 'TIRO III',
  tier_kills integer not null default 0,
  tier_deaths integer not null default 0,
  tier_promoted boolean not null default false,
  matches_won smallint not null default 0,
  matches_lost smallint not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists tournament_player_results_user_idx on public.tournament_player_results (user_id, created_at desc);
create index if not exists tournament_player_results_tournament_idx on public.tournament_player_results (tournament_id);

-- -----------------------------------------------------------------------------
-- 5. Global Leaderboard View
-- -----------------------------------------------------------------------------
drop view if exists public.gunfight_leaderboard cascade;

create view public.gunfight_leaderboard as
select
  p.user_id,
  p.handle,
  p.display_name,
  p.elo_rating,
  p.rank_tier,
  p.major_tier,
  p.tier_kills,
  p.tier_deaths,
  case
    when p.tier_deaths > 0 then round((p.tier_kills::numeric / p.tier_deaths::numeric), 2)
    else p.tier_kills::numeric
  end as current_tier_kd,
  p.lifetime_kills,
  p.lifetime_deaths,
  case
    when p.lifetime_deaths > 0 then round((p.lifetime_kills::numeric / p.lifetime_deaths::numeric), 2)
    else p.lifetime_kills::numeric
  end as lifetime_kd,
  p.tournaments_played,
  p.tournaments_won,
  p.gunfight_matches_won,
  p.gunfight_matches_lost,
  case
    when (p.gunfight_matches_won + p.gunfight_matches_lost) > 0
    then round((p.gunfight_matches_won::numeric / (p.gunfight_matches_won + p.gunfight_matches_lost)::numeric) * 100.0, 1)
    else 0.0
  end as win_rate_percentage
from public.player_profiles p
order by p.elo_rating desc;

-- -----------------------------------------------------------------------------
-- 6. Row Level Security Policies
-- -----------------------------------------------------------------------------
alter table public.player_profiles enable row level security;
alter table public.tournament_matches enable row level security;
alter table public.tournament_player_results enable row level security;

drop policy if exists player_profiles_select on public.player_profiles;
create policy player_profiles_select on public.player_profiles for select using (true);

drop policy if exists player_profiles_insert on public.player_profiles;
create policy player_profiles_insert on public.player_profiles for insert with check (true);

drop policy if exists player_profiles_update on public.player_profiles;
create policy player_profiles_update on public.player_profiles for update using (true);

drop policy if exists tournament_matches_select on public.tournament_matches;
create policy tournament_matches_select on public.tournament_matches for select using (true);

drop policy if exists tournament_matches_insert on public.tournament_matches;
create policy tournament_matches_insert on public.tournament_matches for insert with check (true);

drop policy if exists tournament_player_results_select on public.tournament_player_results;
create policy tournament_player_results_select on public.tournament_player_results for select using (true);

drop policy if exists tournament_player_results_insert on public.tournament_player_results;
create policy tournament_player_results_insert on public.tournament_player_results for insert with check (true);
