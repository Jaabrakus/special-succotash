# 141 restricted Web release

This package is the public browser boundary. It excludes creator labs,
regression tools, editable source art, reference media, design boards, and
development documentation. Scripts are exported as compiled bytecode.

## Build

1. Install the Godot 4.7.1 Web export templates.
2. Run `tools/export_restricted_web.sh`.
3. Upload `builds/SOCOM-141-browser.zip` as an itch.io HTML project, or
   publish the contents of `builds/web/` at another HTTPS origin.
4. Confirm that `robots.txt`, `ai.txt`, the policies, `BUILD_ID.txt`, and
   `SHA256SUMS.txt` are available at the deployed origin.
5. Test in a clean browser profile before sharing the URL.

The preset is single-threaded for broad browser-host compatibility. Recording
is allowed. The launcher displays an ownership watermark without identifying a
player.

## Multiplayer boundary

The restricted browser launcher exposes Quick Match, Browse Servers, and a
direct `wss://` join fallback. Discovery is a public, SELECT-only read of fresh
Supabase `service_regions` and `match_servers` rows. Every successful selection
enters the same canonical multiplayer scene and RPC contract through
`WebSocketMultiplayerPeer`; the browser never becomes the server or a gameplay
owner. Native listen servers continue to use ENet by default.

Before publishing, apply all files in `supabase/migrations/` to the configured
project. In particular, the multiplayer operations tables, directory-presence
columns, and public directory policies must exist. The packaged
`config/supabase_public.json` may contain only the project URL and publishable
key. Keep `SOCOM_SUPABASE_SERVER_KEY` exclusively in the dedicated-server
environment.

Start the authoritative 32-player/eight-arena process with:

```sh
tools/run_browser_multiarena_server.sh
```

The process listens on port `14141` by default. Put that native WebSocket
listener behind a TLS reverse proxy and expose it as a public `wss://` endpoint.
Then set `browser_server_url` in
`config/network/browser_multiarena_deployment.json`, or give players a launch
URL with `?server=wss%3A%2F%2Fyour-host.example%2Fgame`.

An empty `browser_server_url` is intentionally not treated as a deployment.
Quick Match and Browse Servers can still obtain `wss://` endpoints from fresh
directory rows; direct join asks for a full `wss://` address rather than
silently connecting to localhost or an insecure endpoint.

Do not place private server code, credentials, lobby secrets, or signing keys in
the Web package.
