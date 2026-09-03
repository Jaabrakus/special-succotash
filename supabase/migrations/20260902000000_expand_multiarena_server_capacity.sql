-- One dedicated tournament process owns eight isolated 2v2 arena instances.
-- Expand only the server-presence capacity boundary; individual match records
-- retain their existing mode/player constraints and tournament results remain
-- in the dedicated gunfight tournament tables.

alter table public.match_servers
  drop constraint if exists match_servers_current_capacity_check,
  drop constraint if exists match_servers_current_players_check,
  drop constraint if exists match_servers_capacity_check;

alter table public.match_servers
  add constraint match_servers_capacity_check
    check (capacity between 2 and 32),
  add constraint match_servers_current_players_check
    check (current_players between 0 and 32),
  add constraint match_servers_current_capacity_check
    check (current_players <= capacity);
