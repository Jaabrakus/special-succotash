# Render HTTP/WebSocket boundary

Translation card: players connect at the existing secure URL. Acceptance: HTTP
requests return status codes, real Godot traffic round-trips, stopped Godot gives
503, and plain requests never reach its WebSocket parser. Owner: deployment HTTP
gateway. Protected: all gameplay authority, movement, weapons, animations and
client URL. Proof: http_gateway_regression.mjs plus deployment and feature gates.

The public PORT belongs to the gateway; Godot binds 127.0.0.1:17777. The shell
keeps SOCOM_SERVER_PORT as the public advertised port. HTTP / and /healthz probe
a proper local WebSocket handshake, not an incomplete HTTP request. The probe
never submits game actions. Concurrent probes are coalesced. Unknown HTTP paths
are 404; the gateway does not expose files or credentials. WebSocket / and /game
are forwarded with stream backpressure and without interpreting game packets.
The supervisor terminates both processes if either fails, and forwards shutdown.
This checks transport readiness, not Supabase or tournament correctness.

Deployment: commit and push the changed branch, sync the existing Blueprint to
apply healthCheckPath /healthz, then deploy its latest commit. No new service or
plan change. Live verification must check HTTPS /healthz and a game connection.

References: https://render.com/docs/websocket and
https://nodejs.org/api/http.html#event-upgrade ; Godot create_server bind_address
verified using installed 4.7.1 by the real-peer regression.

Local verification 2026-09-06: HTTP 200; unknown path 404; real Godot
WebSocketMultiplayerPeer binary packet roundtrip; backend stopped gives 503;
no incomplete-header messages; supervisor SIGTERM closes both listeners. All
72 feature graphs and the Render deployment regression pass. Docker daemon
unavailable: Linux container build and live Render deployment remain unverified.
The broad quick gate requires main and was not run on codex/render-deployment.

Key implementation excerpts:
`http_gateway.mjs`: `response.writeHead(ready ? 200 : 503, ...)` and
`client.pipe(backend); backend.pipe(client)`.
`start_server.sh`: `export SOCOM_SERVER_BIND_ADDRESS=127.0.0.1` and
`--mp-port=$SOCOM_INTERNAL_PORT`.
`render.dedicated.yaml`: `healthCheckPath: /healthz`.
