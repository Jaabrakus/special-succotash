-- Public browser leaderboard. Expose ranked display data only; keep user ids,
-- player-profile writes, and tournament result commits private.

alter table public.player_profiles
  add column if not exists elo_rating integer not null default 0,
  add column if not exists rank_tier text not null default 'TIRO III',
  add column if not exists major_tier text not null default 'TIRO',
  add column if not exists tier_kills integer not null default 0,
  add column if not exists tier_deaths integer not null default 0,
  add column if not exists lifetime_kills integer not null default 0,
  add column if not exists lifetime_deaths integer not null default 0,
  add column if not exists tournaments_won integer not null default 0,
  add column if not exists tournaments_played integer not null default 0;

create or replace function public.get_public_gunfight_leaderboard(
  p_limit integer default 50
)
returns table (
  display_name text,
  elo_rating integer,
  rank_tier text,
  current_tier_kd numeric,
  win_rate_percentage numeric,
  tournaments_won integer
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    profiles.display_name,
    profiles.elo_rating,
    profiles.rank_tier,
    case
      when profiles.tier_deaths > 0
        then round(profiles.tier_kills::numeric / profiles.tier_deaths::numeric, 2)
      else profiles.tier_kills::numeric
    end as current_tier_kd,
    case
      when profiles.tournaments_played > 0
        then round(
          profiles.tournaments_won::numeric
          / profiles.tournaments_played::numeric
          * 100.0,
          1
        )
      else 0.0
    end as win_rate_percentage,
    profiles.tournaments_won
  from public.player_profiles as profiles
  order by
    profiles.elo_rating desc,
    profiles.tournaments_won desc,
    profiles.updated_at desc
  limit least(greatest(coalesce(p_limit, 50), 1), 100);
$$;

revoke all on function public.get_public_gunfight_leaderboard(integer) from public;
grant execute on function public.get_public_gunfight_leaderboard(integer)
  to anon, authenticated;

