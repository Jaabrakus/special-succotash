-- ============================================================================
-- SOCOM 141 GUNFIGHT TOURNAMENT & PRAETORIAN ELO RATING SCHEMA
-- ============================================================================

create extension if not exists "pgcrypto";

create table if not exists public.player_profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    display_name text not null default 'Nomad',
    elo_rating integer not null default 0,
    rank_tier text not null default 'TIRO III',
    major_tier text not null default 'TIRO',
    tier_kills integer not null default 0,
    tier_deaths integer not null default 0,
    lifetime_kills integer not null default 0,
    lifetime_deaths integer not null default 0,
    tournaments_won integer not null default 0,
    tournaments_played integer not null default 0,
    created_at timestamp with time zone default now(),
    updated_at timestamp with time zone default now()
);

create table if not exists public.gunfight_tournament_matches (
    id uuid primary key default gen_random_uuid(),
    session_id text not null,
    tournament_stage text not null,
    pair_alpha_id integer not null,
    pair_bravo_id integer not null,
    score_alpha integer not null default 0,
    score_bravo integer not null default 0,
    winning_pair_id integer not null,
    arena_pod_index integer not null default 0,
    created_at timestamp with time zone default now()
);

drop view if exists public.gunfight_leaderboard cascade;
create view public.gunfight_leaderboard as
select
    p.user_id,
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
    p.tournaments_won,
    p.tournaments_played,
    case
        when p.tournaments_played > 0 then round((p.tournaments_won::numeric / p.tournaments_played::numeric * 100.0), 1)
        else 0.0
    end as win_rate_percentage,
    p.updated_at
from public.player_profiles p
order by p.elo_rating desc, p.tournaments_won desc, p.updated_at desc;

create or replace function public.handle_new_user()
returns trigger as $$
begin
    insert into public.player_profiles (user_id, display_name, elo_rating, rank_tier, major_tier)
    values (
        new.id,
        coalesce(new.raw_user_meta_data->>'display_name', 'Operator_' || substr(new.id::text, 1, 6)),
        0,
        'TIRO III',
        'TIRO'
    )
    on conflict (user_id) do nothing;
    return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();
