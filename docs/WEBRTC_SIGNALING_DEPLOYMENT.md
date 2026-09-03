# SOCOM-141 browser WebRTC signaling

Private itch browser matches use WebRTC. The first player is authoritative peer
`1`; the free signaling service exchanges only room codes, SDP, and ICE data.
It does not run the map, movement, weapons, damage, or round simulation.

## Deploy the signaling service

1. Push the reviewed project state to the Git repository connected to Render.
2. Create or update a Render Blueprint from the root `render.yaml`.
3. Confirm the Blueprint creates `socom-141-webrtc-signaling` on the Free plan.
4. Deploy and open `/healthz`. The response must contain `"ok":true`.
5. If Render assigns a different hostname, update `webrtc_signaling_url` in
   `config/network/browser_multiarena_deployment.json` before exporting itch.

The expected endpoint is:

```text
wss://socom-141-webrtc-signaling.onrender.com/signal
```

Free Render services can cold-start after they are idle. The game sends a
signaling heartbeat while a room is open. An established WebRTC match continues
peer-to-peer if the signaling socket later drops, but no new player can join.

## Network limits

The default ICE configuration uses STUN and works across many normal home
routers. Strict or symmetric NAT pairs need a TURN service. Add TURN credentials
to `webrtc_ice_servers` only through a short-lived credential system; do not put
long-lived TURN secrets in the browser export.

## Checks

```sh
npm --prefix deploy/signaling test
npm --prefix deploy/signaling audit
```

Then export the restricted Web build, open two independent browser sessions,
host in the first, and paste its `P2P-XXXXXX` code into the second.
