# SOCOM-141 dedicated-server activation

The canonical Godot WebSocket server has a verified Linux container and a
Render Blueprint. It is not publicly reachable until the database migrations
are applied and the Render service is created with its private server key.

## One-time database activation

Apply every SQL file in `supabase/migrations/` in filename order. The order is
part of the contract: the 2026-08-21 service schema creates `match_servers`, the
2026-08-24 operations migration adds `current_players`, and the 2026-09-02
migrations then expand capacity, add browser presence, expose read-only
discovery, and seed the active `gunfight_2v2` ruleset.

The earlier `column "current_players" does not exist` error means the
`20260824002000_create_multiplayer_operations.sql` migration had not been
applied before `20260902001000_add_server_directory_presence.sql`.

Use **Run and enable RLS** when Supabase offers the choice. The migrations
already define the intended policies; public clients receive SELECT-only
directory access, while server writes remain privileged.

## Create the always-on service

1. Push the reviewed project state, including `deploy/server/render.dedicated.yaml`, `deploy/server/`,
   and the runtime resources selected by `deploy/server/Dockerfile.dockerignore`,
   to the private GitHub repository connected to Render.
2. In Render, create a Blueprint from that repository and set Blueprint Path to
   `deploy/server/render.dedicated.yaml`. This optional Blueprint requests
   the paid always-on `1c-2g` service in Virginia. A sleeping free service is
   incompatible with the 45-second directory heartbeat contract.
3. Enter `SOCOM_SUPABASE_SERVER_KEY` in Render's secret prompt. Use a Supabase
   `sb_secret_...` key or the legacy service-role JWT. Never put it in source,
   a browser build, a log, or chat.
4. Deploy. Render supplies `PORT` and `RENDER_EXTERNAL_HOSTNAME`; the entrypoint
   binds that port and advertises `wss://<hostname>` automatically.

Healthy startup must contain both markers:

```text
MP_SLICE DEDICATED_READY transport=websocket port=10000
MP_SLICE CLOUD_REGISTERED
```

Then the public directory should return one fresh `match_servers` row and the
browser's Quick Match button should enter the canonical multiplayer scene.

## Verified local production proof

The Docker image was built from the pinned Godot 4.7.1 Linux binary, ran as the
unprivileged `socom` user, emitted `DEDICATED_READY`, accepted a TCP connection,
returned `HTTP/1.1 101 Switching Protocols`, and sent Godot multiplayer frames.
The smoke test intentionally used a fake server key, so its only cloud warning
was the expected `Invalid API key` response.

Run the static deployment checks again with:

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot \
  --headless --audio-driver Dummy --path . \
  --script res://tools/render_dedicated_server_deployment_regression.gd
```
