-- Durable, idempotent tournament-result ingress for trusted dedicated servers.
-- Realtime input, movement, and shots never use this table.

create extension if not exists "pgcrypto";

-- This migration is intentionally safe to apply to a fresh project as well as
-- one that already ran the earlier Gunfight schema migration. The RPC below
-- records completed arena matches, so PostgreSQL must see this relation when
-- it compiles the function.
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

create table if not exists public.tournament_event_inbox (
    event_id text primary key,
    match_id text not null,
    arena_id integer not null,
    event_type text not null check (event_type in ('ARENA_MATCH_COMPLETED', 'TOURNAMENT_COMPLETED')),
    payload jsonb not null,
    received_at timestamp with time zone not null default now()
);

create index if not exists tournament_event_inbox_match_id_idx
    on public.tournament_event_inbox (match_id, received_at);

create or replace function public.server_record_tournament_event(
    target_event_id text,
    target_match_id text,
    target_arena_id integer,
    target_event_type text,
    target_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    inserted boolean := false;
    inserted_count integer := 0;
    match_row public.gunfight_tournament_matches%rowtype;
begin
    if target_event_id is null or length(trim(target_event_id)) = 0
        or target_match_id is null or length(trim(target_match_id)) = 0
        or target_event_type not in ('ARENA_MATCH_COMPLETED', 'TOURNAMENT_COMPLETED')
        or target_payload is null then
        raise exception 'invalid tournament event';
    end if;

    insert into public.tournament_event_inbox (
        event_id, match_id, arena_id, event_type, payload
    ) values (
        target_event_id, target_match_id, target_arena_id, target_event_type, target_payload
    ) on conflict (event_id) do nothing;
    get diagnostics inserted_count = row_count;
    inserted := inserted_count > 0;

    if not inserted then
        return jsonb_build_object('ok', true, 'duplicate', true, 'event_id', target_event_id);
    end if;

    if target_event_type = 'ARENA_MATCH_COMPLETED' then
        insert into public.gunfight_tournament_matches (
            session_id,
            tournament_stage,
            pair_alpha_id,
            pair_bravo_id,
            score_alpha,
            score_bravo,
            winning_pair_id,
            arena_pod_index
        ) values (
            target_match_id,
            coalesce(target_payload->>'stage', 'UNKNOWN'),
            (target_payload->>'pair_alpha_id')::integer,
            (target_payload->>'pair_bravo_id')::integer,
            greatest(0, coalesce((target_payload->>'score_alpha')::integer, 0)),
            greatest(0, coalesce((target_payload->>'score_bravo')::integer, 0)),
            (target_payload->>'winner_pair_id')::integer,
            target_arena_id
        ) returning * into match_row;
    end if;

    -- ELO and rewards intentionally wait for a trusted account-id mapping.
    -- The inbox is the durable source record that will make those updates safe.
    return jsonb_build_object(
        'ok', true,
        'duplicate', false,
        'event_id', target_event_id,
        'match_record_id', case when match_row.id is null then null else match_row.id end
    );
end;
$$;

revoke all on function public.server_record_tournament_event(text, text, integer, text, jsonb) from public;
grant execute on function public.server_record_tournament_event(text, text, integer, text, jsonb) to service_role;
