# Community map backend

This folder tracks the database and Storage contract for publishing community maps. Local Map Lab editing does not require Supabase and remains fully offline.

## Layout

- `migrations/`: ordered SQL migrations, compatible with the Supabase CLI.
- Community map JSON and version metadata live in Postgres.
- Self-contained GLB assets live in the private `community-map-assets` Storage bucket.
- Storage keys use `<owner_uuid>/<map_uuid>/<sha256>.glb`.
- `20260821001000_create_authoritative_game_services.sql` adds player profiles,
  approved gameplay rulesets, loadouts, matchmaking, dedicated-server discovery,
  match rosters, final statistics, and round results.

Live movement, weapon firing, ammo, hit validation, damage, recoil/composure, and
demolition state do not use database writes. Those remain owned by the dedicated
Godot match server; only that trusted server may publish match and round results.
The server schema can record each participant's measured RTT, jitter, and packet
loss for diagnostics. The shared 130 ms remote-player presentation buffer remains
owned by the existing multiplayer code and is not controlled by Supabase.

Never commit a service-role key. Public server discovery uses only the browser-safe
publishable key plus SELECT-only RLS. Player profiles, tickets, moderation, and
all other private player data still require the signed-in player's JWT.

The exported client endpoint and publishable key live in
`res://config/supabase_public.json`. Local development may override them with
the ignored `res://config/supabase.json`. Neither file may contain a secret or
service-role key; dedicated servers read `SOCOM_SUPABASE_SERVER_KEY` from their
process environment.

Apply locally with `supabase db reset`, or to a linked project with `supabase db push`, after reviewing the migration for the target environment.

The public launcher is not live until all ordered migrations have been pushed,
at least one healthy `service_regions` row exists, and a dedicated server is
publishing a reachable `wss://` address in `match_servers`. Anonymous Auth is
optional for server discovery but must be enabled for automatic guest profiles,
leaderboards, parties, and future ticket-based matchmaking.
