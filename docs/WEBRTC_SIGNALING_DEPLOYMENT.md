# SOCOM-141 32-player browser tournament signaling

The itch browser build uses WebRTC for the public 32-player tournament. Players
click one tournament action; they do not host a private 2v2 or paste a room
code. The signaling service automatically creates and fills a tournament room.

The first player in each room is authoritative peer `1`. The signaling service
exchanges only tournament-room assignment, SDP, and ICE data. It does not run
the map, movement, weapons, damage, rounds, arena isolation, or bracket.

## Deploy the signaling service

1. Apply `supabase/migrations/20260902004000_public_gunfight_leaderboard.sql`.
2. Push the reviewed project state to the Git repository connected to Render.
3. Create or update a Render Blueprint from the root `render.yaml`.
4. Confirm the Blueprint creates `socom-141-webrtc-signaling` on the Free plan
   with `SOCOM_WEBRTC_MAX_TOURNAMENT_PEERS=32`.
5. Deploy and open `/healthz`. The response must contain `"ok":true` and
   `"tournament_capacity":32`.
6. If Render assigns a different hostname, update `webrtc_signaling_url` in
   `config/network/browser_multiarena_deployment.json` before the itch export.

The expected endpoint is:

```text
wss://socom-141-webrtc-signaling.onrender.com/signal
```

Free Render services can cold-start after they are idle. The game sends a
signaling heartbeat while a room is open. An established WebRTC tournament can
continue if signaling later drops, but no new player can join.

## Known transport limits

Godot's client/server WebRTC mode gives each client one connection to peer `1`;
the host has up to 31 client connections. This avoids a 32-peer full mesh, but
peer `1` still simulates the authoritative tournament. If peer `1` leaves, that
tournament ends because host migration is not implemented.

The default ICE configuration uses STUN and works across many normal home
routers. Strict or symmetric NAT pairs need a TURN service. Add TURN credentials
only through a short-lived credential system; never put long-lived TURN secrets
in the browser export.

## Checks

```sh
npm --prefix deploy/signaling test
npm --prefix deploy/signaling audit
```

Then export the restricted Web build and open independent browser profiles.
Each profile must join the same automatic `TOUR-XXXXXX` room until it reaches 32
players; the next player starts the next tournament room.
